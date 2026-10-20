/* Copyright (C) 2026 Mihawk; SPDX-License-Identifier: GPL-3.0-or-later */
/* The WebUI's transfer engine, apart from HTTP (src/webui_ps5.cpp wires it).
 *
 * Three ways in, all ending the same way: a file is written under a hidden
 * temporary name beside its destination and renamed into place only when every
 * byte is there, so a transfer cut short never leaves a partial file behind.
 *
 *   - one file, one request (PUT /api/upload), written in 1 MiB blocks;
 *   - many small files, one request (PUT /api/upload/batch): a stream of records,
 *     so thousands of files cost one round trip per batch instead of one per file;
 *   - one large file, several requests at once (an upload session): byte ranges
 *     arrive in any order on as many connections as the client opens, each written
 *     at its own offset, and the file is committed once its ranges cover it.
 *
 * The server answers on several threads (a pool), so these are thread-safe: a
 * session's ranges under its own lock, renames under one commit lock. */
#pragma once
#include <cstddef>
#include <cstdint>
#include <ctime>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace ps5_transfer
{
constexpr size_t write_block = 1u << 20;

/* Writes a stream through a block buffer, from a start offset (pwrite), so one file
 * can take several writers at different offsets. */
class Writer
{
  public:
    Writer() = default;
    Writer(const Writer &) = delete;
    Writer &operator=(const Writer &) = delete;
    ~Writer();
    /* A new file, created exclusive; the writer owns and closes it. */
    bool create(const std::string &path);
    /* Someone else's descriptor (a session's), from offset. */
    void attach(int fd, uint64_t offset);
    bool write(const char *data, size_t size);
    bool flush();
    int fd() const
    {
        return fd_;
    }
    uint64_t written() const
    {
        return written_;
    }
    /* Flushes, then gives the descriptor up (the caller closes an owned one). */
    int release();

  private:
    int fd_ = -1;
    bool owned_ = false;
    uint64_t offset_ = 0, written_ = 0;
    std::vector<char> buffer_;
    size_t used_ = 0;
};

/* Moves a finished temporary file to its destination: never over an existing file
 * unless replace. Every rename goes through one lock, so two writers of the same
 * name cannot both pass the existence check. data_fd (or -1) is synced first. */
enum class Commit
{
    done,
    exists,
    failed
};
Commit commit(int data_fd, const std::string &temporary, const std::string &destination,
              bool replace, bool sync);

/* The batch stream: records of
 *     u16 name length (little-endian), name (a path below the batch folder),
 *     u64 size, size bytes of data,
 * ended by a name length of 0. The reader takes the body in whatever pieces it
 * arrives in and calls the sink at each record's start, data and end. */
class BatchSink
{
  public:
    virtual ~BatchSink() = default;
    /* A record starts: false skips its data (the reason is the sink's to keep). */
    virtual bool begin(const std::string &name, uint64_t size) = 0;
    virtual bool data(const char *bytes, size_t size) = 0;
    virtual void end() = 0;
};
class BatchReader
{
  public:
    explicit BatchReader(BatchSink &sink) : sink_(sink)
    {
    }
    /* false once the stream is malformed (an empty or oversized name, data past the
     * end marker); the files before it stand. */
    bool feed(const char *data, size_t size);
    bool finished() const
    {
        return state_ == State::done;
    }
    const char *problem() const
    {
        return problem_;
    }
    unsigned records() const
    {
        return records_;
    }

  private:
    enum class State
    {
        name_length,
        name,
        size,
        data,
        done,
        bad
    };
    BatchSink &sink_;
    State state_ = State::name_length;
    unsigned char header_[8] = {};
    size_t have_ = 0, name_length_ = 0;
    std::string name_;
    uint64_t remaining_ = 0;
    bool accepted_ = false;
    unsigned records_ = 0;
    const char *problem_ = "";
    bool fail(const char *why);
};

/* One large file arriving in ranges (an upload session). */
struct Session
{
    std::string id, temporary, destination;
    uint64_t size = 0;
    bool replace = false;
    int fd = -1;
    std::mutex lock;
    std::map<uint64_t, uint64_t> ranges; /* start -> end, merged */
    uint64_t covered = 0;
    unsigned writers = 0;
    bool closing = false;
    std::time_t touched = 0;
    /* Records [start, end) as received; under lock. */
    void add(uint64_t start, uint64_t end);
};
class Sessions
{
  public:
    /* A new session, its temporary file created and sized; nullptr with why set. */
    std::shared_ptr<Session> open(const std::string &id, const std::string &temporary,
                                  const std::string &destination, uint64_t size, bool replace,
                                  const char *&why);
    std::shared_ptr<Session> find(const std::string &id);
    /* Takes the session out (commit or abort); its file is the caller's then. */
    std::shared_ptr<Session> take(const std::string &id);
    /* Drops sessions idle for longer than seconds (their temporary files deleted). */
    void expire(std::time_t now, std::time_t seconds);
    /* Every session gone, as the server stops. */
    void clear();
    size_t count();
    static constexpr size_t limit = 16;

  private:
    std::mutex lock_;
    std::map<std::string, std::shared_ptr<Session>> sessions_;
};
/* Closes and deletes a session's file (abort, expiry). */
void discard(Session &session);

/* "bytes=a-b" (one range) against a file's size: false when absent or unusable. */
bool parse_range(const char *header, uint64_t size, uint64_t &start, uint64_t &end);
} // namespace ps5_transfer
