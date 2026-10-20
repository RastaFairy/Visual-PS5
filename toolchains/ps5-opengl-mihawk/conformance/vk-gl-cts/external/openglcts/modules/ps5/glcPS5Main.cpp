// PS5 OpenGL - OpenGL implementation for PlayStation 5.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

#include "glcPS5GL33PackageEntry.hpp"

#include "deUniquePtr.hpp"
#include "qpDebugOut.h"
#include "glcTestPackageRegistry.hpp"
#include "glcTestRunner.hpp"
#include "gluRenderContext.hpp"
#include "tcuApp.hpp"
#include "tcuCommandLine.hpp"
#include "tcuPlatform.hpp"
#include "tcuResource.hpp"
#include "tcuTestLog.hpp"
#include "tcuTestPackage.hpp"

#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <exception>
#include <signal.h>
#include <ucontext.h>
#include <unistd.h>
#include <unwind.h>
#include <pthread.h>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <time.h>
#include <vector>

extern "C" int sceKernelDebugOutText(int channel, const char *text);
struct LibcMallocManagedSize {
  uint16_t size;
  uint16_t version;
  uint32_t reserved;
  size_t maxSystemSize;
  size_t currentSystemSize;
  size_t maxInuseSize;
  size_t currentInuseSize;
};
extern "C" void malloc_stats_fast(LibcMallocManagedSize *stats);
extern "C" void psbc_glsl_type_cache_print_stats(unsigned iteration);
extern "C" void ps5_opengl_heap_stats_print(unsigned iteration);
extern "C" void ps5_opengl_heap_snapshot(const char *phase, unsigned iteration);
extern "C" size_t ps5_opengl_heap_live_bytes(void);
// Test case objects (and their buffers) live as long as the package, which
// needs far more than the default native-app heap.
extern "C" const size_t ps5_opengl_heap_size = size_t(1) << 30;
// Zero-filled heap memory: some test cases delete object names held in members
// they never initialized (KHR-GL46.fragment_shading_rate.render_target.* when
// the extension is not supported). With heap garbage those deletes hit
// unrelated live objects and change the result of later cases at random.
extern "C" const int ps5_opengl_heap_zero_fill = 1;

// Whether operator new really returns zero-filled memory for a recycled block.
bool heapZeroFilled() {
  for (int round = 0; round < 64; ++round) {
    volatile unsigned char *block = new unsigned char[256];
    bool zero = true;
    for (int i = 0; i < 256; ++i) {
      zero &= block[i] == 0;
      block[i] = 0xa5;
    }
    delete[] block;
    if (!zero)
      return false;
  }
  return true;
}

tcu::Platform *createPlatform(void);
int main(void);

namespace {

constexpr const char *kArgumentsPath = "/app0/cts-args.txt";
constexpr const char *kStatusPath = "/download0/ps5-opengl-cts.status";
constexpr const char *kRunnerMarkerPath = "/app0/cts-runner.txt";
constexpr int kMaxArguments = 64;
constexpr int kMaxArgumentLength = 512;

void printHeapStats(unsigned iteration) {
  ps5_opengl_heap_stats_print(iteration);
  if (iteration == 14) {
    LibcMallocManagedSize stats = {sizeof(stats), 1, 0, 0, 0, 0, 0};
    malloc_stats_fast(&stats);
    std::printf("[ps5-opengl-cts] libc-heap max-system=%zu current-system=%zu "
                "max-inuse=%zu current-inuse=%zu\n",
                stats.maxSystemSize, stats.currentSystemSize,
                stats.maxInuseSize, stats.currentInuseSize);
  }
  psbc_glsl_type_cache_print_stats(iteration);
  using Mallctl = int (*)(const char *, void *, size_t *, void *, size_t);
  static Mallctl mallctl =
      reinterpret_cast<Mallctl>(dlsym(RTLD_DEFAULT, "mallctl"));
  if (mallctl == nullptr)
    return;

  uint64_t epoch = 1;
  size_t epochSize = sizeof(epoch);
  size_t allocated = 0;
  size_t allocatedSize = sizeof(allocated);
  if (mallctl("epoch", &epoch, &epochSize, &epoch, sizeof(epoch)) == 0 &&
      mallctl("stats.allocated", &allocated, &allocatedSize, nullptr, 0) == 0)
    std::printf("[ps5-opengl-cts] heap iteration=%u allocated=%zu\n",
                iteration, allocated);
}

struct Arguments {
  int count = 1;
  char storage[kMaxArguments - 1][kMaxArgumentLength] = {};
  const char *values[kMaxArguments + 1] = {"ps5-gl33-cts"};
};

void writeStatus(const char *state, const tcu::TestRunStatus *result) {
  FILE *file = std::fopen(kStatusPath, "w");
  if (file == nullptr)
    return;

  if (result == nullptr)
    std::fprintf(file, "state=%s\n", state);
  else
    std::fprintf(file,
                 "state=%s complete=%d executed=%d passed=%d failed=%d "
                 "not_supported=%d warnings=%d waived=%d device_lost=%d\n",
                 state, result->isComplete ? 1 : 0, result->numExecuted,
                 result->numPassed, result->numFailed,
                 result->numNotSupported, result->numWarnings,
                 result->numWaived, result->numDeviceLost);
  std::fclose(file);
}

int finish(const char *state, int exitCode,
           const tcu::TestRunStatus *result = nullptr) {
  writeStatus(state, result);
  std::printf("[ps5-opengl-cts] finished state=%s", state);
  if (result != nullptr)
    std::printf(" executed=%d failed=%d device_lost=%d", result->numExecuted,
                result->numFailed, result->numDeviceLost);
  std::printf("\n");
  std::fflush(stdout);
  sceKernelDebugOutText(0, "[ps5-opengl-cts] finished\n");
  return exitCode;
}

bool startsWith(const char *value, const char *prefix) {
  return std::strncmp(value, prefix, std::strlen(prefix)) == 0;
}

bool loadArguments(Arguments &arguments) {
  FILE *file = std::fopen(kArgumentsPath, "r");
  if (file == nullptr) {
    std::fprintf(stderr, "missing CTS argument file: %s\n", kArgumentsPath);
    return false;
  }

  bool hasCaseSelection = false;
  char line[kMaxArgumentLength];
  while (std::fgets(line, sizeof(line), file) != nullptr) {
    if (std::strchr(line, '\n') == nullptr && !std::feof(file)) {
      std::fprintf(stderr, "overlong CTS argument\n");
      std::fclose(file);
      return false;
    }

    char *argument = line;
    while (*argument == ' ' || *argument == '\t')
      ++argument;

    char *end = argument + std::strlen(argument);
    while (end != argument && (end[-1] == '\r' || end[-1] == '\n' ||
                               end[-1] == ' ' || end[-1] == '\t'))
      *--end = '\0';

    if (*argument == '\0' || *argument == '#')
      continue;
    if (!startsWith(argument, "--deqp-")) {
      std::fprintf(stderr, "invalid CTS argument: %s\n", argument);
      std::fclose(file);
      return false;
    }
    if (std::strcmp(argument, "--deqp-watchdog=enable") == 0 ||
        std::strcmp(argument, "--deqp-crashhandler=enable") == 0) {
      std::fprintf(stderr, "unsafe CTS runtime option: %s\n", argument);
      std::fclose(file);
      return false;
    }
    if (arguments.count >= kMaxArguments) {
      std::fprintf(stderr, "too many CTS arguments\n");
      std::fclose(file);
      return false;
    }

    hasCaseSelection |= startsWith(argument, "--deqp-case=") ||
                        startsWith(argument, "--deqp-caselist=") ||
                        startsWith(argument, "--deqp-caselist-file=");
    char *stored = arguments.storage[arguments.count - 1];
    std::strcpy(stored, argument);
    arguments.values[arguments.count++] = stored;
  }

  std::fclose(file);
  arguments.values[arguments.count] = nullptr;

  if (!hasCaseSelection)
    std::fprintf(stderr,
                 "CTS run requires an explicit bounded case selection\n");
  return hasCaseSelection;
}

// Crash evidence for klog: signal, fault address and return addresses, with
// the address of main so the frames can be symbolized against the eboot.
_Unwind_Reason_Code printFrame(struct _Unwind_Context *context, void *depth) {
  int &frames = *static_cast<int *>(depth);
  char line[64];
  std::snprintf(line, sizeof(line), "[ps5-opengl-cts] frame %d 0x%lx\n", frames,
                (unsigned long)_Unwind_GetIP(context));
  sceKernelDebugOutText(0, line);
  return ++frames < 48 ? _URC_NO_REASON : _URC_END_OF_STACK;
}

void printBacktrace(const char *reason) {
  char line[160];
  std::snprintf(line, sizeof(line), "[ps5-opengl-cts] crash %s main=0x%lx\n", reason,
                (unsigned long)(uintptr_t)&main);
  sceKernelDebugOutText(0, line);
  int frames = 0;
  _Unwind_Backtrace(printFrame, &frames);
}

void crashSignal(int signal, siginfo_t *info, void *) {
  char reason[64];
  std::snprintf(reason, sizeof(reason), "signal=%d addr=0x%lx", signal,
                (unsigned long)(uintptr_t)(info ? info->si_addr : nullptr));
  printBacktrace(reason);
  _exit(128 + signal);
}

void installCrashHandlers(void) {
  struct sigaction action;
  std::memset(&action, 0, sizeof(action));
  action.sa_sigaction = crashSignal;
  action.sa_flags = SA_SIGINFO;
  for (int signal : {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT})
    sigaction(signal, &action, nullptr);
  std::set_terminate([] {
    printBacktrace("terminate");
    _exit(134);
  });
}

// Per-case watchdog (control key watchdog=<seconds>): a case that makes no
// progress gets a backtrace of the main thread in klog instead of a silent
// hang, then the process exits so the host can resume after it.
volatile time_t g_lastCaseStart = 0;
int g_watchdogSeconds = 0;
pthread_t g_mainThread;
const uintptr_t *g_mainStackBase = nullptr;

void watchdogSignal(int, siginfo_t *, void *raw) {
  // The unwinder stops at the signal frame: report the interrupted PC and the
  // code addresses on the interrupted stack (return addresses, innermost first).
  const ucontext_t *context = static_cast<const ucontext_t *>(raw);
  const uintptr_t text = (uintptr_t)&main & ~(uintptr_t)0x3fffff;
  char line[96];
  std::snprintf(line, sizeof(line), "[ps5-opengl-cts] crash watchdog main=0x%lx\n",
                (unsigned long)(uintptr_t)&main);
  sceKernelDebugOutText(0, line);
  std::snprintf(line, sizeof(line), "[ps5-opengl-cts] frame 0 0x%lx\n",
                (unsigned long)context->uc_mcontext.mc_rip);
  sceKernelDebugOutText(0, line);
  const uintptr_t *stack = (const uintptr_t *)context->uc_mcontext.mc_rsp;
  int frames = 1;
  for (int i = 0; i < 4096 && frames < 40; ++i) {
    const uintptr_t value = stack[i];
    if (value >= text && value < text + 0x8000000u) {
      std::snprintf(line, sizeof(line), "[ps5-opengl-cts] frame %d 0x%lx\n", frames++,
                    (unsigned long)value);
      sceKernelDebugOutText(0, line);
    }
  }
  std::fflush(stdout);
  _exit(142);
}

void *watchdogThread(void *) {
  // Keep the signal off this thread so the stuck main thread reports itself.
  sigset_t blocked;
  sigemptyset(&blocked);
  sigaddset(&blocked, SIGUSR1);
  pthread_sigmask(SIG_BLOCK, &blocked, nullptr);
  for (;;) {
    sleep(5);
    const time_t last = g_lastCaseStart;
    if (last && time(nullptr) - last > g_watchdogSeconds) {
      sceKernelDebugOutText(0, "[ps5-opengl-cts] watchdog expired\n");
      // Driver diagnostics up to the stall are still in the stdout buffer.
      std::fflush(stdout);
      // Signals land on this thread here, so read the stuck main thread's
      // stack directly: code addresses from its base downward are the live
      // call chain (outermost first), followed by stale deeper frames.
      {
        const uintptr_t text = (uintptr_t)&main & ~(uintptr_t)0x3fffff;
        char line[96];
        std::snprintf(line, sizeof(line), "[ps5-opengl-cts] crash watchdog-stack main=0x%lx\n",
                      (unsigned long)(uintptr_t)&main);
        sceKernelDebugOutText(0, line);
        int frames = 0;
        for (const uintptr_t *slot = g_mainStackBase;
             frames < 160 && slot > g_mainStackBase - 32768; --slot) {
          const uintptr_t value = *slot;
          if (value >= text && value < text + 0x8000000u) {
            std::snprintf(line, sizeof(line), "[ps5-opengl-cts] frame %d 0x%lx\n", frames++,
                          (unsigned long)value);
            sceKernelDebugOutText(0, line);
          }
        }
      }
      kill(getpid(), SIGUSR1);
      sleep(5);
      _exit(143);
    }
  }
  return nullptr;
}

void startWatchdog(int seconds) {
  if (seconds <= 0)
    return;
  struct sigaction action;
  std::memset(&action, 0, sizeof(action));
  action.sa_sigaction = watchdogSignal;
  action.sa_flags = SA_SIGINFO;
  sigaction(SIGUSR1, &action, nullptr);
  g_watchdogSeconds = seconds;
  g_mainThread = pthread_self();
  g_mainStackBase = (const uintptr_t *)__builtin_frame_address(0);
  pthread_t thread;
  pthread_create(&thread, nullptr, watchdogThread, nullptr);
}

void noteCaseStart(const char *message) {
  if (std::strstr(message, "Test case '"))
    g_lastCaseStart = time(nullptr);
}

// dEQP's own output (per-case lines, tcu::die messages) goes to klog.
bool klogOut(int, const char *message) {
  noteCaseStart(message);
  sceKernelDebugOutText(0, message);
  return false; // handled: skip the stdout copy
}

bool klogOutFormat(int, const char *format, va_list args) {
  char line[1024];
  std::vsnprintf(line, sizeof(line), format, args);
  noteCaseStart(line);
  sceKernelDebugOutText(0, line);
  return false;
}

void redirectToKlog(void) { qpRedirectOut(klogOut, klogOutFormat); }

// Conformance runner mode, enabled by /app0/cts-runner.txt. The host writes
// /app0/cts-results/control.txt (FTP: /data/homebrew/PPSA99005/cts-results):
//   run=<name>                  output directory below /app0/cts-results
//   mode=official|sessions      official: upstream cts-runner in one launch
//   first=<n> last=<n>          sessions: 1-based session range (default all)
//   logflush=0                  buffered QPA logs (--deqp-log-flush=disable)
//   only_caselists=1            run only sessions with a host-written case list
//   shader_sources=1            log shader sources (diagnostic reruns only)
//   env=<NAME>=<value>          set a driver environment variable (repeatable)
// Official mode runs glcts::TestRunner unchanged, as `cts-runner --type=gl46
// --logdir=<run>` does. Sessions mode first asks the same runner for its
// session list (--summary), then runs each session with exactly those
// arguments, skipping sessions that already have a .status file, so a run can
// be batched over several launches. A host-written <log>.caselist replaces the
// session's case list to resume after a crash; that log goes to <log>.resume.
namespace runner {

constexpr const char *kRoot = "/app0/cts-results";

struct Control {
  std::string run = "default";
  std::string mode = "sessions";
  int first = 1;
  int last = 1 << 30;
  bool logFlush = true;
  bool onlyCaseLists = false;
  bool shaderSources = false;
  bool dumpNir = false;
  bool computeSync = false;
  bool logImages = false;
  int watchdog = 0;
  std::vector<std::string> env;
};

struct Session {
  std::string fileName;
  std::vector<std::string> args;
};

void klog(const char *format, ...) {
  char line[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(line, sizeof(line), format, args);
  va_end(args);
  sceKernelDebugOutText(0, line);
}

bool fileExists(const std::string &path) {
  struct stat info;
  return stat(path.c_str(), &info) == 0;
}

std::string readFile(const std::string &path) {
  std::ifstream stream(path.c_str(), std::ios::binary);
  std::stringstream text;
  text << stream.rdbuf();
  return text.str();
}

Control readControl(void) {
  Control control;
  std::istringstream text(readFile(std::string(kRoot) + "/control.txt"));
  std::string line;
  while (std::getline(text, line)) {
    const size_t equals = line.find('=');
    if (equals == std::string::npos)
      continue;
    const std::string key = line.substr(0, equals);
    std::string value = line.substr(equals + 1);
    while (!value.empty() && (value.back() == '\r' || value.back() == ' '))
      value.pop_back();
    if (key == "run")
      control.run = value;
    else if (key == "mode")
      control.mode = value;
    else if (key == "first")
      control.first = std::atoi(value.c_str());
    else if (key == "last")
      control.last = std::atoi(value.c_str());
    else if (key == "logflush")
      control.logFlush = value != "0";
    else if (key == "only_caselists")
      control.onlyCaseLists = value == "1";
    else if (key == "shader_sources")
      control.shaderSources = value == "1";
    else if (key == "dump_nir")
      control.dumpNir = value == "1";
    else if (key == "compute_sync")
      control.computeSync = value == "1";
    else if (key == "log_images")
      control.logImages = value == "1";
    else if (key == "watchdog")
      control.watchdog = std::atoi(value.c_str());
    else if (key == "env")
      control.env.push_back(value);
  }
  return control;
}

std::string attribute(const std::string &element, const char *name) {
  const std::string key = std::string(name) + "=\"";
  const size_t start = element.find(key);
  if (start == std::string::npos)
    return std::string();
  const size_t end = element.find('"', start + key.size());
  return element.substr(start + key.size(), end - start - key.size());
}

// Sessions in the order and with the arguments of the upstream run summary.
std::vector<Session> readPlan(const std::string &summaryPath) {
  std::vector<Session> sessions;
  const std::string xml = readFile(summaryPath);
  size_t position = 0;
  while ((position = xml.find("<TestRun ", position)) != std::string::npos) {
    const size_t end = xml.find('>', position);
    const std::string element = xml.substr(position, end - position);
    Session session;
    session.fileName = attribute(element, "FileName");
    std::istringstream words(attribute(element, "CmdLine"));
    std::string word;
    while (words >> word)
      session.args.push_back(word);
    sessions.push_back(session);
    position = end;
  }
  return sessions;
}

void writeSessionStatus(const std::string &path, const tcu::TestRunStatus &result,
                        double seconds) {
  FILE *file = std::fopen(path.c_str(), "w");
  if (file == nullptr)
    return;
  std::fprintf(file,
               "complete=%d executed=%d passed=%d failed=%d not_supported=%d "
               "warnings=%d waived=%d device_lost=%d seconds=%.1f\n",
               result.isComplete ? 1 : 0, result.numExecuted, result.numPassed,
               result.numFailed, result.numNotSupported, result.numWarnings,
               result.numWaived, result.numDeviceLost, seconds);
  std::fclose(file);
}

double now(void) {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec + value.tv_nsec * 1e-9;
}

// One session, as glcts::TestRunner::initSession builds it without verbose flags.
void runSession(tcu::Platform &platform, tcu::Archive &archive, const std::string &dir,
                const Session &session, int index, int count, bool logFlush,
                bool shaderSources, bool logImages) {
  std::vector<std::string> args = session.args;
  std::string logName = session.fileName;
  const std::string caseList = dir + "/" + session.fileName + ".caselist";
  if (fileExists(caseList)) {
    for (std::string &arg : args)
      if (arg.rfind("--deqp-caselist-resource=", 0) == 0 ||
          arg.rfind("--deqp-caselist-file=", 0) == 0)
        arg = "--deqp-caselist-file=" + caseList;
    logName += ".resume";
  }
  // Supplementary runs: the cases that insist on a window surface (see the
  // platform port) run with the same offscreen surface declared as a window.
  if (std::getenv("PS5_CTS_OFFSCREEN_WINDOW") != nullptr)
    for (std::string &arg : args)
      if (arg == "--deqp-surface-type=pbuffer")
        arg = "--deqp-surface-type=window";
  args.push_back("--deqp-log-filename=" + dir + "/" + logName);
  if (!logImages)
    args.push_back("--deqp-log-images=disable");
  // Shader sources help diagnose compiler failures in focused reruns.
  if (!shaderSources)
    args.push_back("--deqp-log-shader-sources=disable");
  // Flushing every QPA line costs ~30 ms on the title folder; per-case progress
  // is in klog either way.
  if (!logFlush)
    args.push_back("--deqp-log-flush=disable");

  std::vector<const char *> argv;
  argv.push_back("cts-runner");
  for (const std::string &arg : args)
    argv.push_back(arg.c_str());

  klog("[ps5-opengl-cts] session %d/%d start %s\n", index, count, logName.c_str());
  const double start = now();
  tcu::CommandLine commandLine((int)argv.size(), argv.data());
  tcu::TestLog log(commandLine.getLogFileName(), commandLine.getLogFlags());
  log.writeSessionInfo(std::string("#sessionInfo commandLineParameters \"") +
                       commandLine.getInitialCmdLine() + "\"\n");
  tcu::App app(platform, archive, log, commandLine);
  // Report cases that grow the owned heap: klog pairs this with the case name.
  size_t heap = ps5_opengl_heap_live_bytes();
  int executed = 0;
  while (app.iterate()) {
    const int done = app.getResult().numExecuted;
    if (done != executed) {
      executed = done;
      const size_t now_bytes = ps5_opengl_heap_live_bytes();
      if (now_bytes > heap + (8u << 20))
        klog("[ps5-opengl-cts] heap grew %zu KiB to %zu KiB\n", (now_bytes - heap) >> 10,
             now_bytes >> 10);
      heap = now_bytes;
    }
  }
  const tcu::TestRunStatus result = app.getResult();
  const double seconds = now() - start;
  writeSessionStatus(dir + "/" + logName + ".status", result, seconds);
  klog("[ps5-opengl-cts] session %d/%d done executed=%d passed=%d failed=%d "
       "not_supported=%d warnings=%d complete=%d seconds=%.0f\n",
       index, count, result.numExecuted, result.numPassed, result.numFailed,
       result.numNotSupported, result.numWarnings, result.isComplete ? 1 : 0, seconds);
}

} // namespace runner

int runConformance(void) {
  using namespace runner;
  installCrashHandlers();
  setvbuf(stdout, nullptr, _IOLBF, 0);
  try {
    const Control control = readControl();
    const std::string dir = std::string(kRoot) + "/" + control.run;
    mkdir(kRoot, 0777);
    mkdir(dir.c_str(), 0777);
    // The runner's own output (per-case lines, tcu::die messages) goes to a
    // file next to the logs; klog carries only the progress markers.
    redirectToKlog();
    startWatchdog(control.watchdog);
    if (control.dumpNir)
      setenv("PSBC_DUMP_NIR", "1", 1);
    if (control.computeSync)
      setenv("PS5_COMPUTE_SYNC", "1", 1);
    for (const std::string &variable : control.env) {
      const size_t equals = variable.find('=');
      if (equals != std::string::npos && equals != 0)
        setenv(variable.substr(0, equals).c_str(), variable.substr(equals + 1).c_str(), 1);
    }
    // Driver diagnostics (printf) go to a buffered file next to the logs.
    if (std::freopen((dir + "/stdout.txt").c_str(), "a", stdout) != nullptr)
      setvbuf(stdout, nullptr, _IOFBF, 1 << 16);
    // Unbuffered: compiler diagnostics must survive the abort that follows them.
    if (std::freopen((dir + "/stderr.txt").c_str(), "a", stderr) != nullptr)
      setvbuf(stderr, nullptr, _IONBF, 0);
    std::atexit([] { runner::klog("[ps5-opengl-cts] exit() called\n"); });
    klog("[ps5-opengl-cts] runner mode=%s run=%s first=%d last=%d\n",
         control.mode.c_str(), control.run.c_str(), control.first, control.last);
    if (!heapZeroFilled())
      throw std::runtime_error("heap memory is not zero-filled");
    klog("[ps5-opengl-cts] heap zero-fill verified\n");

    glcts::registerPackages();
    tcu::DirArchive archive("/app0");
    de::UniquePtr<tcu::Platform> platform(createPlatform());
    klog("[ps5-opengl-cts] runner platform ready\n");

    if (control.mode == "official") {
      glcts::TestRunner official(*platform, archive, "", dir.c_str(),
                                 glu::ApiType::core(4, 6), 0);
      while (official.iterate()) {
      }
      klog("[ps5-opengl-cts] official run finished\n");
      return finish("runner_finished", 0);
    }

    const std::string planDir = dir + "/plan";
    const std::string planPath = planDir + "/cts-run-summary.xml";
    if (!fileExists(planPath)) {
      mkdir(planDir.c_str(), 0777);
      klog("[ps5-opengl-cts] runner writing plan\n");
      glcts::TestRunner summary(*platform, archive, "", planDir.c_str(),
                                glu::ApiType::core(4, 6),
                                glcts::TestRunner::PRINT_SUMMARY);
      while (summary.iterate()) {
      }
    }
    const std::vector<Session> sessions = readPlan(planPath);
    klog("[ps5-opengl-cts] plan sessions=%d\n", (int)sessions.size());
    const int count = (int)sessions.size();
    // cts-runner's first run lists the EGL configs; it is not a summary TestRun.
    if (control.first <= 1 && !control.onlyCaseLists && !fileExists(dir + "/configs.qpa.status")) {
      Session configs;
      configs.fileName = "configs.qpa";
      configs.args.push_back("--deqp-case=CTS-Configs.*");
      runSession(*platform, archive, dir, configs, 0, count, control.logFlush,
                 control.shaderSources, control.logImages);
    }
    for (int index = std::max(control.first, 1);
         index <= std::min(control.last, count); ++index) {
      const Session &session = sessions[index - 1];
      const std::string caseList = dir + "/" + session.fileName + ".caselist";
      const std::string status = dir + "/" + session.fileName +
                                 (fileExists(caseList) ? ".resume" : "") + ".status";
      if (fileExists(status) || (control.onlyCaseLists && !fileExists(caseList)))
        continue;
      runSession(*platform, archive, dir, session, index, count, control.logFlush,
                 control.shaderSources, control.logImages);
    }
    klog("[ps5-opengl-cts] sessions finished\n");
    return finish("runner_finished", 0);
  } catch (const std::exception &error) {
    runner::klog("[ps5-opengl-cts] runner fatal: %s\n", error.what());
    return finish("fatal", 3);
  }
}

} // anonymous namespace

int main(void) {
  writeStatus("starting", nullptr);
  std::printf("[ps5-opengl-cts] starting OpenGL CTS runner\n");
  // Negative tests intentionally raise millions of GL errors. Suppress only
  // Mesa's stderr duplicates; glGetError, debug callbacks and QPA stay enabled.
  if (setenv("MESA_DEBUG", "silent", 1) != 0)
    return finish("logging_setup_error", 2);
  if (FILE *marker = std::fopen(kRunnerMarkerPath, "r")) {
    std::fclose(marker);
    return runConformance();
  }

  try {
    Arguments arguments;
    if (!loadArguments(arguments)) {
      return finish("argument_error", 2);
    }

    for (int index = 1; index < arguments.count; ++index)
      std::printf("[ps5-opengl-cts] arg %s\n", arguments.values[index]);

    glctsRegisterPS5GL33Package();
    tcu::CommandLine commandLine(arguments.count, arguments.values);
    tcu::DirArchive archive(commandLine.getArchiveDir());
    tcu::TestLog log(commandLine.getLogFileName(), commandLine.getLogFlags());
    de::UniquePtr<tcu::Platform> platform(createPlatform());
    tcu::App app(*platform, archive, log, commandLine);

    unsigned iteration = 0;
    int completedCases = -1;
    ps5_opengl_heap_snapshot("cts-start", 0);
    while (app.iterate()) {
      printHeapStats(++iteration);
      const tcu::TestRunStatus progress = app.getResult();
      if (progress.numExecuted != completedCases) {
        completedCases = progress.numExecuted;
        ps5_opengl_heap_snapshot("cts-progress", completedCases);
        writeStatus("running", &progress);
        std::fflush(stdout);
      }
    }

    const tcu::TestRunStatus result = app.getResult();
    ps5_opengl_heap_snapshot("cts-finished", result.numExecuted);
    // Match the upstream tcuMain acceptance rule. The GL must-pass list also
    // contains optional-extension cases, for which NotSupported is valid.
    const bool passed = result.isComplete && result.numExecuted > 0 &&
                        result.numFailed == 0 && result.numDeviceLost == 0;
    return finish(passed ? "passed" : "failed", passed ? 0 : 1, &result);
  } catch (const std::exception &error) {
    std::fprintf(stderr, "[ps5-opengl-cts] fatal: %s\n", error.what());
    return finish("fatal", 3);
  }
}
