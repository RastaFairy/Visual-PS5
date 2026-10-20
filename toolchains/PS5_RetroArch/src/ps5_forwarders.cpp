/* PS5 RetroArch - Game Forwarder tiles (src/ps5_forwarders.h).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ShadowMountPlus's API, as its docs/api.md (1.7) describes it: every call a POST of one
 * JSON object, every answer a JSON object whose "status" is 0 on success, else an errno
 * with "error" and, when busy, "error_reason". Removing a manual source does not
 * uninstall its title, and uninstalling keeps the source, which a later scan installs
 * again: a tile leaves the list before it is uninstalled, and is re-registered by an
 * uninstall and a scan.
 */
#include "ps5_forwarders.h"

#include "scraper_json.h"

#include <algorithm>
#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <map>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace ps5_forwarders
{
namespace
{
using ps5_scraper::Json;
constexpr unsigned first_number = 99170, last_number = 99269;
constexpr size_t icon_limit = 2 << 20;
const char *const no_shadowmount =
    "ShadowMountPlus does not answer on 127.0.0.1:10101. Game Forwarder tiles need it: "
    "load ShadowMountPlus 1.7 or later, with its API enabled (api_enabled=1, the default).";

std::string quote(const std::string &text)
{
    std::string out = "\"";
    for (unsigned char c : text)
    {
        if (c == '"' || c == '\\')
            out += '\\', out += char(c);
        else if (c < 32)
        {
            char escape[7];
            std::snprintf(escape, sizeof escape, "\\u%04x", c);
            out += escape;
        }
        else
            out += char(c);
    }
    return out + '"';
}
bool tile_id(const std::string &id)
{
    if (id.size() != 9 || id.compare(0, 4, "PPSA") != 0 ||
        !std::all_of(id.begin() + 4, id.end(), [](char c) { return c >= '0' && c <= '9'; }))
        return false;
    const unsigned number = unsigned(std::atoi(id.c_str() + 4));
    return number >= first_number && number <= last_number;
}
std::string read_file(const std::string &path, size_t limit)
{
    std::string out;
    const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW);
    if (fd < 0)
        return out;
    char buffer[16384];
    ssize_t got;
    while (out.size() < limit && (got = read(fd, buffer, sizeof buffer)) > 0)
        out.append(buffer, size_t(got));
    close(fd);
    return out;
}
bool exists(const std::string &path)
{
    struct stat st{};
    return lstat(path.c_str(), &st) == 0;
}
/* Whole, or not at all: written beside, then renamed over. */
bool write_file(const std::string &path, const std::string &data)
{
    const std::string temporary = path + ".part";
    const int fd = open(temporary.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0)
        return false;
    size_t done = 0;
    while (done < data.size())
    {
        const ssize_t wrote = write(fd, data.data() + done, data.size() - done);
        if (wrote <= 0)
            break;
        done += size_t(wrote);
    }
    const bool ok =
        close(fd) == 0 && done == data.size() && rename(temporary.c_str(), path.c_str()) == 0;
    if (!ok)
        unlink(temporary.c_str());
    return ok;
}
bool copy_file(const std::string &from, const std::string &to)
{
    const std::string data = read_file(from, 64 << 20);
    return !data.empty() && write_file(to, data);
}
/* A tile's folder and what is in it; no other file system is entered (a mount inside
 * stays, and so does the folder). */
void remove_tree(const std::string &path)
{
    struct stat top{};
    if (lstat(path.c_str(), &top) != 0 || !S_ISDIR(top.st_mode))
        return;
    std::vector<std::string> names;
    if (DIR *dir = opendir(path.c_str()))
    {
        while (const dirent *entry = readdir(dir))
            if (std::strcmp(entry->d_name, ".") != 0 && std::strcmp(entry->d_name, "..") != 0)
                names.push_back(entry->d_name);
        closedir(dir);
    }
    for (const auto &name : names)
    {
        const std::string child = path + '/' + name;
        struct stat st{};
        if (lstat(child.c_str(), &st) != 0)
            continue;
        if (!S_ISDIR(st.st_mode))
            unlink(child.c_str());
        else if (st.st_dev == top.st_dev)
            remove_tree(child);
    }
    rmdir(path.c_str());
}

/* ---- ShadowMountPlus ---------------------------------------------------------------- */
/* One call: its answer, or a null value and why when none came. HTTP/1.0, so the answer
 * comes whole and the connection closes after it, as ShadowMountPlus closes it anyway. */
Json call(const Paths &paths, const char *route, const std::string &body,
          std::string *why = nullptr)
{
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return Json();
    timeval timeout{5, 0}, answer_timeout{20, 0}; /* the game list reads app.db */
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &answer_timeout, sizeof answer_timeout);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(paths.shadowmount_port);
    inet_pton(AF_INET, paths.shadowmount_host.c_str(), &address.sin_addr);
    std::string reply, problem;
    if (connect(fd, reinterpret_cast<const sockaddr *>(&address), sizeof address) != 0)
        problem = std::string("no connection (") + std::strerror(errno) + ')';
    else
    {
        const std::string request =
            std::string("POST ") + route + " HTTP/1.0\r\nHost: " + paths.shadowmount_host +
            "\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(body.size()) +
            "\r\n\r\n" + body;
#ifdef MSG_NOSIGNAL
        const int flags = MSG_NOSIGNAL;
#else
        const int flags = 0;
#endif
        if (send(fd, request.data(), request.size(), flags) == ssize_t(request.size()))
        {
            char buffer[16384];
            ssize_t got = 0;
            while (reply.size() < (16u << 20) && (got = recv(fd, buffer, sizeof buffer, 0)) > 0)
                reply.append(buffer, size_t(got));
            if (got < 0)
                problem = "the answer stopped after " + std::to_string(reply.size()) + " bytes (" +
                          std::strerror(errno) + ')';
        }
        else
            problem = std::string("the request was not sent (") + std::strerror(errno) + ')';
    }
    close(fd);
    const size_t head = reply.find("\r\n\r\n");
    const Json answer = reply.compare(0, 5, "HTTP/") == 0 && head != std::string::npos
                            ? Json::parse(reply.substr(head + 4))
                            : Json();
    if (why && !problem.empty())
        *why = problem;
    else if (why)
        *why = answer.kind == Json::object
                   ? ""
                   : "the answer (" + std::to_string(reply.size()) + " bytes) is not JSON";
    return answer;
}
bool succeeded(const Json &answer)
{
    return answer["status"].kind == Json::number && answer["status"].value == 0;
}
std::string failure(const Json &answer)
{
    if (answer.kind != Json::object)
        return no_shadowmount;
    const std::string reason = answer["error_reason"].str();
    return answer["error"].str() + (reason.empty() ? "" : " (" + reason + ")");
}
std::string path_body(const Paths &paths, const std::string &id)
{
    return "{\"path\":" + quote(paths.homebrew + '/' + id) + '}';
}
struct Known
{
    bool answers = false;
    std::string version, why;
    std::map<std::string, bool> titles; /* every title ShadowMountPlus knows: installed */
};
Known known(const Paths &paths)
{
    Known out;
    out.why = no_shadowmount;
    const Json version = call(paths, "/api/v1/version", "{}");
    if (!succeeded(version))
        return out;
    out.version = version["shadowmount_version"].str();
    std::string why;
    const Json games = call(paths, "/api/v1/games", "{\"include_size\":false}", &why);
    if (!succeeded(games))
    {
        out.why = "ShadowMountPlus " + out.version +
                  " did not list its games: " + (why.empty() ? failure(games) : why);
        return out;
    }
    out.answers = true;
    out.why.clear();
    for (const Json &game : games["games"].items)
        out.titles[game["title_id"].str()] = game["installed"].flag;
    return out;
}
bool installed(const Known &smp, const std::string &id)
{
    const auto found = smp.titles.find(id);
    return found != smp.titles.end() && found->second;
}

/* ---- tiles ---------------------------------------------------------------------------- */
std::string folder_of(const Paths &paths, const std::string &id)
{
    return paths.homebrew + '/' + id;
}
/* A folder of the range holding the tile's arguments: made here. */
bool is_tile(const Paths &paths, const std::string &id)
{
    return tile_id(id) && exists(folder_of(paths, id) + "/forward.txt");
}
std::vector<std::string> tile_ids(const Paths &paths)
{
    std::vector<std::string> out;
    for (unsigned number = first_number; number <= last_number; ++number)
        if (is_tile(paths, "PPSA" + std::to_string(number)))
            out.push_back("PPSA" + std::to_string(number));
    return out;
}
/* forward.txt: one argument a line, as forwarder/launch.c reads it. */
std::string forward_text(const Tile &tile)
{
    return "--rom\n" + tile.rom + '\n' + (tile.core.empty() ? "" : "--core\n" + tile.core + '\n') +
           (tile.exit_after_game ? "--exit-after-game\n" : "");
}
Tile read_tile(const Paths &paths, const std::string &id)
{
    Tile tile;
    tile.exit_after_game = false;
    const std::string folder = folder_of(paths, id),
                      text = read_file(folder + "/forward.txt", 8192);
    std::vector<std::string> lines;
    for (size_t start = 0; start < text.size();)
    {
        size_t end = text.find('\n', start);
        if (end == std::string::npos)
            end = text.size();
        std::string line = text.substr(start, end - start);
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (!line.empty())
            lines.push_back(line);
        start = end + 1;
    }
    for (size_t i = 0; i < lines.size(); ++i)
        if (lines[i] == "--exit-after-game")
            tile.exit_after_game = true;
        else if (lines[i] == "--rom" && i + 1 < lines.size())
            tile.rom = lines[++i];
        else if (lines[i] == "--core" && i + 1 < lines.size())
            tile.core = lines[++i];
    const Json param = Json::parse(read_file(folder + "/sce_sys/param.json", 65536));
    const Json &names = param["localizedParameters"];
    tile.name = names[names["defaultLanguage"].str()]["titleName"].str();
    return tile;
}
/* RetroArch's own param.json (sce_sys/param.json), for this tile's id and name: the one
 * the forwarder spike's tile carried on the console. */
std::string param_json(const std::string &id, const std::string &name)
{
    const std::string number = id.substr(4);
    return "{\n"
           "  \"ageLevel\": {\n    \"default\": 0\n  },\n"
           "  \"applicationCategoryType\": 0,\n"
           "  \"applicationDrmType\": \"free\",\n"
           "  \"attribute\": 0,\n  \"attribute2\": 0,\n  \"attribute3\": 524352,\n"
           "  \"conceptId\": \"" +
           number +
           "\",\n"
           "  \"contentBadgeType\": 1,\n"
           "  \"contentId\": \"UP9000-" +
           id + "_00-FORWARDER00" + number +
           "\",\n"
           "  \"contentVersion\": \"01.000.000\",\n"
           "  \"downloadDataSize\": 256,\n"
           "  \"gameIntent\": {\n    \"permittedIntents\": [\n      {\n"
           "        \"intentType\": \"launchActivity\"\n      }\n    ]\n  },\n"
           "  \"kernel\": {\n    \"flexibleMemorySize\": 1073741824\n  },\n"
           "  \"localizedParameters\": {\n    \"defaultLanguage\": \"en-US\",\n"
           "    \"en-US\": {\n      \"titleName\": " +
           quote(name) +
           "\n    }\n  },\n"
           "  \"masterVersion\": \"01.00\",\n"
           "  \"pubtools\": {\n    \"creationDate\": \"2026-09-18 00:00:00\",\n"
           "    \"loudnessSnd0\": \"-28.00\",\n    \"toolVersion\": \"2.00\"\n  },\n"
           "  \"requiredSystemSoftwareVersion\": \"0x0000000000000000\",\n"
           "  \"sdkVersion\": \"0x0000000000000000\",\n"
           "  \"titleId\": \"" +
           id +
           "\",\n"
           "  \"versionFileUri\": \"\"\n"
           "}\n";
}
bool plain(const std::string &text)
{
    return std::none_of(text.begin(), text.end(),
                        [](unsigned char c) { return c < 32 || c == 127; });
}
/* What a tile may hold: a name, a game of the library (inside the content folder, or on a
 * USB or extended storage drive, as the library reads them), a core the title has. */
bool check(const Paths &paths, const Tile &tile, std::string &why)
{
    const bool drive = tile.rom.rfind("/mnt/usb", 0) == 0 || tile.rom.rfind("/mnt/ext", 0) == 0;
    bool parent = false;
    for (size_t at = 0; at <= tile.rom.size();)
    {
        size_t end = tile.rom.find('/', at);
        if (end == std::string::npos)
            end = tile.rom.size();
        parent = parent || (end - at == 2 && tile.rom.compare(at, 2, "..") == 0);
        at = end + 1;
    }
    if (tile.name.find_first_not_of(' ') == std::string::npos || tile.name.size() > 128 ||
        !plain(tile.name))
        why = "Give the tile a name (up to 128 bytes, on one line).";
    else if (tile.rom.empty() || (tile.rom[0] == '/' && !drive) || parent || !plain(tile.rom) ||
             !exists(drive ? tile.rom : paths.title + "/content/" + tile.rom))
        why = "Choose a game from your library.";
    else if (!tile.core.empty() &&
             (!std::all_of(
                  tile.core.begin(), tile.core.end(), [](char c)
                  { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; }) ||
              !exists(paths.title + "/cores/" + tile.core + "_libretro.so")))
        why = "This core is not in RetroArch.";
    else
        return true;
    return false;
}
/* The title's cores: id (cores/<id>_libretro.so) and name (its .info's corename). */
std::string cores_json(const Paths &paths)
{
    static const std::string suffix = "_libretro.so";
    std::vector<std::pair<std::string, std::string>> cores;
    if (DIR *dir = opendir((paths.title + "/cores").c_str()))
    {
        while (const dirent *entry = readdir(dir))
        {
            const std::string file = entry->d_name;
            if (file.size() <= suffix.size() ||
                file.compare(file.size() - suffix.size(), suffix.size(), suffix) != 0)
                continue;
            const std::string id = file.substr(0, file.size() - suffix.size());
            std::string name = id;
            const std::string info =
                read_file(paths.title + "/info/" + id + "_libretro.info", 65536);
            const size_t key = info.find("\ncorename");
            const size_t open = info.find('"', key);
            const size_t close = info.find('"', open + 1);
            if (key != std::string::npos && close != std::string::npos &&
                info.find('\n', key + 1) > close)
                name = info.substr(open + 1, close - open - 1);
            cores.emplace_back(name, id);
        }
        closedir(dir);
    }
    std::sort(cores.begin(), cores.end());
    std::string out;
    for (const auto &core : cores)
        out += (out.empty() ? "" : ",") + std::string("{\"id\":") + quote(core.second) +
               ",\"name\":" + quote(core.first) + '}';
    return '[' + out + ']';
}
const char *const remove_marker = "/remove.pending", *const refresh_marker = "/refresh.pending";
/* A new name or icon reaches the home screen when the tile is installed again. */
void mark_refresh(const Paths &paths, const std::string &id)
{
    if (installed(known(paths), id))
        write_file(folder_of(paths, id) + refresh_marker, "");
}
} // namespace

std::string list_json(const Paths &paths)
{
    const Known smp = known(paths);
    std::string tiles;
    for (const auto &id : tile_ids(paths))
    {
        const Tile tile = read_tile(paths, id);
        const std::string folder = folder_of(paths, id);
        const char *state = exists(folder + remove_marker)    ? "removing"
                            : exists(folder + refresh_marker) ? "updating"
                            : !smp.answers                    ? "unknown"
                            : installed(smp, id)              ? "installed"
                                                              : "waiting";
        tiles += (tiles.empty() ? "" : ",") + std::string("{\"id\":") + quote(id) +
                 ",\"name\":" + quote(tile.name) + ",\"rom\":" + quote(tile.rom) +
                 ",\"core\":" + quote(tile.core) +
                 ",\"exit_after_game\":" + (tile.exit_after_game ? "true" : "false") +
                 ",\"state\":\"" + state + "\"}";
    }
    return "{\"shadowmount\":{\"answers\":" + std::string(smp.answers ? "true" : "false") +
           ",\"version\":" + quote(smp.version) + ",\"error\":" + quote(smp.why) +
           "},\"first\":\"PPSA" + std::to_string(first_number) + "\",\"last\":\"PPSA" +
           std::to_string(last_number) + "\",\"cores\":" + cores_json(paths) + ",\"tiles\":[" +
           tiles + "]}";
}

bool parse_tile(const std::string &json, Tile &tile, std::string &why)
{
    const Json value = Json::parse(json);
    if (value.kind != Json::object)
    {
        why = "The tile's details did not arrive. Try again.";
        return false;
    }
    tile.name = value["name"].str();
    while (!tile.name.empty() && tile.name.back() == ' ')
        tile.name.pop_back();
    tile.rom = value["rom"].str();
    tile.core = value["core"].str();
    tile.exit_after_game =
        value["exit_after_game"].kind != Json::boolean || value["exit_after_game"].flag;
    return true;
}

bool create(const Paths &paths, const Tile &tile, std::string &id, std::string &why)
{
    id.clear();
    if (!check(paths, tile, why))
        return false;
    const Known smp = known(paths);
    if (!smp.answers)
    {
        why = smp.why;
        return false;
    }
    /* an id no folder has and ShadowMountPlus knows nowhere (an installed title, or one
     * on a disk it scans) */
    for (unsigned number = first_number; number <= last_number && id.empty(); ++number)
    {
        const std::string candidate = "PPSA" + std::to_string(number);
        if (!exists(folder_of(paths, candidate)) && !smp.titles.count(candidate))
            id = candidate;
    }
    if (id.empty())
    {
        why = "Every tile id (PPSA" + std::to_string(first_number) + " to PPSA" +
              std::to_string(last_number) + ") is taken. Delete a tile first.";
        return false;
    }
    const std::string folder = folder_of(paths, id);
    /* forward.txt last: a folder without it is no tile */
    bool made = mkdir(folder.c_str(), 0755) == 0 &&
                mkdir((folder + "/sce_sys").c_str(), 0755) == 0 &&
                mkdir((folder + "/sce_module").c_str(), 0755) == 0 &&
                copy_file(paths.title + "/forwarder/eboot.bin", folder + "/eboot.bin") &&
                copy_file(paths.title + "/forwarder/launch.elf", folder + "/launch.elf") &&
                copy_file(paths.title + "/sce_module/libc.prx", folder + "/sce_module/libc.prx") &&
                copy_file(paths.title + "/sce_sys/icon0.png", folder + "/sce_sys/icon0.png") &&
                write_file(folder + "/sce_sys/param.json", param_json(id, tile.name)) &&
                write_file(folder + "/forward.txt", forward_text(tile));
    if (!made)
        why = "The tile could not be written to " + folder + " (" + std::strerror(errno) +
              "). Check free space, and that RetroArch's folder is complete.";
    else
    {
        const Json added = call(paths, "/api/v1/manual/add", path_body(paths, id));
        made = succeeded(added);
        if (!made)
            why = "ShadowMountPlus did not take the tile: " + failure(added);
    }
    if (!made)
    {
        remove_tree(folder);
        id.clear();
    }
    return made;
}

bool update(const Paths &paths, const std::string &id, const Tile &tile, std::string &why)
{
    if (!is_tile(paths, id))
    {
        why = "There is no such tile.";
        return false;
    }
    if (!check(paths, tile, why))
        return false;
    const std::string folder = folder_of(paths, id);
    const Tile before = read_tile(paths, id);
    if (!write_file(folder + "/forward.txt", forward_text(tile)) ||
        (tile.name != before.name &&
         !write_file(folder + "/sce_sys/param.json", param_json(id, tile.name))))
    {
        why = "The tile could not be saved. Check free space.";
        return false;
    }
    if (tile.name != before.name)
        mark_refresh(paths, id);
    return true;
}

bool set_icon(const Paths &paths, const std::string &id, const std::string &png, std::string &why)
{
    auto big_endian = [&](size_t at)
    {
        return unsigned(uint8_t(png[at])) << 24 | unsigned(uint8_t(png[at + 1])) << 16 |
               unsigned(uint8_t(png[at + 2])) << 8 | unsigned(uint8_t(png[at + 3]));
    };
    if (!is_tile(paths, id))
        why = "There is no such tile.";
    else if (png.size() < 33 || png.size() > icon_limit ||
             png.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0 || png.compare(12, 4, "IHDR") != 0 ||
             big_endian(16) != 512 || big_endian(20) != 512)
        why = "The icon must be a PNG of 512 x 512 pixels, up to 2 MiB.";
    else if (!write_file(folder_of(paths, id) + "/sce_sys/icon0.png", png))
        why = "The icon could not be saved. Check free space.";
    else
    {
        mark_refresh(paths, id);
        return true;
    }
    return false;
}

std::string icon_file(const Paths &paths, const std::string &id)
{
    return is_tile(paths, id) ? folder_of(paths, id) + "/sce_sys/icon0.png" : "";
}

std::string remove(const Paths &paths, const std::string &id, std::string &why)
{
    if (!is_tile(paths, id))
    {
        why = "There is no such tile.";
        return "";
    }
    const Known smp = known(paths);
    if (!smp.answers)
    {
        why = smp.why;
        return "";
    }
    /* out of the list first, or a scan installs it again */
    const Json removed = call(paths, "/api/v1/manual/remove", path_body(paths, id));
    if (!succeeded(removed))
    {
        why = "ShadowMountPlus did not let the tile go: " + failure(removed);
        return "";
    }
    if (installed(smp, id) &&
        !succeeded(call(paths, "/api/v1/games/uninstall", "{\"title_id\":" + quote(id) + '}')))
    {
        /* refused while a game runs, and RetroArch is one: once the title has closed */
        if (!write_file(folder_of(paths, id) + remove_marker, ""))
        {
            why = "The tile could not be marked for removal. Check free space.";
            return "";
        }
        return "pending";
    }
    remove_tree(folder_of(paths, id));
    return "removed";
}

bool finish_pending(const Paths &paths, void (*say)(const char *line))
{
    char line[512];
    size_t left = 0;
    std::vector<std::string> removals, refreshes;
    for (const auto &id : tile_ids(paths))
    {
        const std::string folder = folder_of(paths, id);
        if (exists(folder + remove_marker))
        {
            removals.push_back(id);
            continue;
        }
        if (exists(folder + refresh_marker))
            refreshes.push_back(id);
        /* the app and the payload this build carries */
        for (const char *name : {"eboot.bin", "launch.elf"})
        {
            const std::string current = read_file(paths.title + "/forwarder/" + name, 64 << 20);
            if (!current.empty() && current != read_file(folder + '/' + name, 64 << 20))
            {
                std::snprintf(line, sizeof line, "forwarder %s: %s %s", id.c_str(), name,
                              write_file(folder + '/' + name, current) ? "brought up to this build"
                                                                       : "could not be replaced");
                say(line);
            }
        }
    }
    if (removals.empty() && refreshes.empty())
        return true;
    const Known smp = known(paths);
    if (!smp.answers)
    {
        std::snprintf(line, sizeof line, "forwarders: removals and new names or icons wait: %s",
                      smp.why.c_str());
        say(line);
        return false;
    }
    std::vector<std::string> uninstalled;
    for (const auto &id : removals)
    {
        const Json gone = installed(smp, id) ? call(paths, "/api/v1/games/uninstall",
                                                    "{\"title_id\":" + quote(id) + '}')
                                             : Json::parse("{\"status\":0}");
        if (!succeeded(gone))
        {
            ++left;
            std::snprintf(line, sizeof line, "forwarder %s: not removed yet: %s", id.c_str(),
                          failure(gone).c_str());
        }
        else
        {
            remove_tree(folder_of(paths, id));
            std::snprintf(line, sizeof line, "forwarder %s: removed", id.c_str());
        }
        say(line);
    }
    for (const auto &id : refreshes)
    {
        const Json gone = installed(smp, id) ? call(paths, "/api/v1/games/uninstall",
                                                    "{\"title_id\":" + quote(id) + '}')
                                             : Json::parse("{\"status\":0}");
        if (succeeded(gone))
            uninstalled.push_back(id);
        else
        {
            ++left;
            std::snprintf(line, sizeof line, "forwarder %s: not re-registered yet: %s", id.c_str(),
                          failure(gone).c_str());
            say(line);
        }
    }
    if (uninstalled.empty())
        return left == 0;
    /* the uninstall finishes on its own: then a scan installs each one again */
    for (int wait = 0; wait < 40; ++wait)
    {
        const Known now = known(paths);
        if (std::none_of(uninstalled.begin(), uninstalled.end(),
                         [&](const std::string &id) { return installed(now, id); }))
            break;
        usleep(500000);
    }
    /* back in the list first: ShadowMountPlus 1.7-beta5fix1 can drop a source from it as it
     * installs (its next scan reads app.db before the install shows there) */
    for (const auto &id : uninstalled)
        call(paths, "/api/v1/manual/add", path_body(paths, id));
    const bool scanned = succeeded(call(paths, "/api/v1/scan", "{\"reset_attempts\":true}"));
    for (const auto &id : uninstalled)
    {
        if (scanned)
            unlink((folder_of(paths, id) + refresh_marker).c_str());
        std::snprintf(line, sizeof line, "forwarder %s: %s", id.c_str(),
                      scanned ? "installed again with its new name or icon"
                              : "uninstalled; ShadowMountPlus did not take the scan");
        say(line);
    }
    return left == 0 && scanned;
}
} // namespace ps5_forwarders
