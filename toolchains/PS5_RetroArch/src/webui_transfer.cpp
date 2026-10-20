/* Copyright (C) 2026 Mihawk; SPDX-License-Identifier: GPL-3.0-or-later */
/* The WebUI's transfer engine (src/webui_transfer.h says what each part is for). */
#include "webui_transfer.h"

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace ps5_transfer
{
Writer::~Writer()
{
    if (owned_ && fd_ >= 0)
        close(fd_);
}

bool Writer::create(const std::string &path)
{
    fd_ = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
    owned_ = fd_ >= 0;
    offset_ = written_ = 0;
    return owned_;
}

void Writer::attach(int fd, uint64_t offset)
{
    fd_ = fd;
    owned_ = false;
    offset_ = offset;
    written_ = 0;
}

bool Writer::write(const char *data, size_t size)
{
    if (fd_ < 0)
        return false;
    if (buffer_.empty())
        buffer_.resize(write_block);
    while (size)
    {
        /* A piece as large as the block goes straight to the file. */
        if (used_ == 0 && size >= write_block)
        {
            const size_t whole = size - size % write_block;
            const ssize_t n = pwrite(fd_, data, whole, static_cast<off_t>(offset_ + written_));
            if (n < 0 && errno == EINTR)
                continue;
            if (n <= 0)
                return false;
            written_ += uint64_t(n);
            data += n;
            size -= size_t(n);
            continue;
        }
        const size_t take = std::min(size, write_block - used_);
        std::memcpy(buffer_.data() + used_, data, take);
        used_ += take;
        data += take;
        size -= take;
        if (used_ == write_block && !flush())
            return false;
    }
    return true;
}

bool Writer::flush()
{
    size_t done = 0;
    while (done < used_)
    {
        const ssize_t n = pwrite(fd_, buffer_.data() + done, used_ - done,
                                 static_cast<off_t>(offset_ + written_));
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return false;
        done += size_t(n);
        written_ += uint64_t(n);
    }
    used_ = 0;
    return true;
}

int Writer::release()
{
    const int fd = flush() ? fd_ : -1;
    if (fd < 0 && owned_ && fd_ >= 0)
        close(fd_);
    fd_ = -1;
    owned_ = false;
    return fd;
}

namespace
{
std::mutex commit_lock;
}

Commit commit(int data_fd, const std::string &temporary, const std::string &destination,
              bool replace, bool sync)
{
    if (data_fd >= 0 && sync && fsync(data_fd))
        return Commit::failed;
    std::lock_guard<std::mutex> guard(commit_lock);
    if (!replace)
    {
        /* Opened, not stat'ed: a title cannot use lstat reliably (src/webui_ps5.cpp). */
        const int existing = open(destination.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
        if (existing >= 0 || errno != ENOENT)
        {
            if (existing >= 0)
                close(existing);
            return Commit::exists;
        }
    }
    return rename(temporary.c_str(), destination.c_str()) == 0 ? Commit::done : Commit::failed;
}

bool BatchReader::fail(const char *why)
{
    if (accepted_)
        sink_.end();
    accepted_ = false;
    state_ = State::bad;
    problem_ = why;
    return false;
}

bool BatchReader::feed(const char *data, size_t size)
{
    while (size || (state_ == State::data && remaining_ == 0))
    {
        switch (state_)
        {
        case State::bad:
            return false;
        case State::done:
            return size == 0 || fail("The batch has data after its end.");
        case State::name_length:
        case State::size:
        {
            const size_t want = state_ == State::name_length ? 2 : 8;
            const size_t take = std::min(size, want - have_);
            std::memcpy(header_ + have_, data, take);
            have_ += take;
            data += take;
            size -= take;
            if (have_ < want)
                break;
            have_ = 0;
            if (state_ == State::name_length)
            {
                name_length_ = size_t(header_[0]) | size_t(header_[1]) << 8;
                if (name_length_ == 0)
                    state_ = State::done;
                else if (name_length_ > 1024)
                    return fail("A file name in the batch is too long.");
                else
                {
                    name_.clear();
                    state_ = State::name;
                }
            }
            else
            {
                remaining_ = 0;
                for (int i = 7; i >= 0; --i)
                    remaining_ = remaining_ << 8 | header_[i];
                accepted_ = sink_.begin(name_, remaining_);
                ++records_;
                state_ = State::data;
            }
            break;
        }
        case State::name:
        {
            const size_t take = std::min(size, name_length_ - name_.size());
            name_.append(data, take);
            data += take;
            size -= take;
            if (name_.size() == name_length_)
                state_ = State::size;
            break;
        }
        case State::data:
        {
            const size_t take = size_t(std::min<uint64_t>(size, remaining_));
            if (accepted_ && take && !sink_.data(data, take))
                accepted_ = false; /* the sink keeps why; the rest is drained */
            data += take;
            size -= take;
            remaining_ -= take;
            if (remaining_ == 0)
            {
                if (accepted_)
                    sink_.end();
                accepted_ = false;
                state_ = State::name_length;
            }
            break;
        }
        }
    }
    return state_ != State::bad;
}

void Session::add(uint64_t start, uint64_t end)
{
    if (start >= end)
        return;
    auto next = ranges.upper_bound(start);
    if (next != ranges.begin())
    {
        auto previous = std::prev(next);
        if (previous->second >= start)
        {
            start = previous->first;
            end = std::max(end, previous->second);
            covered -= previous->second - previous->first;
            ranges.erase(previous);
        }
    }
    next = ranges.lower_bound(start);
    while (next != ranges.end() && next->first <= end)
    {
        end = std::max(end, next->second);
        covered -= next->second - next->first;
        next = ranges.erase(next);
    }
    ranges[start] = end;
    covered += end - start;
}

std::shared_ptr<Session> Sessions::open(const std::string &id, const std::string &temporary,
                                        const std::string &destination, uint64_t size, bool replace,
                                        const char *&why)
{
    std::lock_guard<std::mutex> guard(lock_);
    if (sessions_.size() >= limit)
    {
        why = "Too many large uploads at once. Wait for one to finish.";
        return nullptr;
    }
    auto session = std::make_shared<Session>();
    session->id = id;
    session->temporary = temporary;
    session->destination = destination;
    session->size = size;
    session->replace = replace;
    session->touched = std::time(nullptr);
    session->fd = ::open(temporary.c_str(), O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
    if (session->fd < 0)
    {
        why = "Could not create the upload. Check console storage.";
        return nullptr;
    }
    /* Sized now, so ranges land anywhere; sparse until written. */
    if (ftruncate(session->fd, static_cast<off_t>(size)))
    {
        close(session->fd);
        unlink(temporary.c_str());
        why = "There is not enough free space on the console.";
        return nullptr;
    }
    sessions_[id] = session;
    return session;
}

std::shared_ptr<Session> Sessions::find(const std::string &id)
{
    std::lock_guard<std::mutex> guard(lock_);
    auto it = sessions_.find(id);
    return it == sessions_.end() ? nullptr : it->second;
}

std::shared_ptr<Session> Sessions::take(const std::string &id)
{
    std::lock_guard<std::mutex> guard(lock_);
    auto it = sessions_.find(id);
    if (it == sessions_.end())
        return nullptr;
    auto session = it->second;
    sessions_.erase(it);
    return session;
}

void discard(Session &session)
{
    std::lock_guard<std::mutex> guard(session.lock);
    session.closing = true;
    if (session.writers == 0 && session.fd >= 0)
    {
        close(session.fd);
        session.fd = -1;
    }
    unlink(session.temporary.c_str());
}

void Sessions::expire(std::time_t now, std::time_t seconds)
{
    std::vector<std::shared_ptr<Session>> stale;
    {
        std::lock_guard<std::mutex> guard(lock_);
        for (auto it = sessions_.begin(); it != sessions_.end();)
        {
            std::lock_guard<std::mutex> session_guard(it->second->lock);
            if (it->second->writers == 0 && now - it->second->touched > seconds)
            {
                stale.push_back(it->second);
                it = sessions_.erase(it);
            }
            else
                ++it;
        }
    }
    for (auto &session : stale)
        discard(*session);
}

void Sessions::clear()
{
    std::map<std::string, std::shared_ptr<Session>> all;
    {
        std::lock_guard<std::mutex> guard(lock_);
        all.swap(sessions_);
    }
    for (auto &entry : all)
        discard(*entry.second);
}

size_t Sessions::count()
{
    std::lock_guard<std::mutex> guard(lock_);
    return sessions_.size();
}

bool parse_range(const char *header, uint64_t size, uint64_t &start, uint64_t &end)
{
    if (!header || std::strncmp(header, "bytes=", 6) != 0 || size == 0)
        return false;
    const char *p = header + 6;
    char *after = nullptr;
    if (*p == '-')
    {
        /* The last n bytes. */
        const uint64_t last = std::strtoull(p + 1, &after, 10);
        if (after == p + 1 || *after || last == 0)
            return false;
        start = last >= size ? 0 : size - last;
        end = size;
        return true;
    }
    start = std::strtoull(p, &after, 10);
    if (after == p || *after != '-' || start >= size)
        return false;
    p = after + 1;
    if (*p == '\0')
    {
        end = size;
        return true;
    }
    const uint64_t last = std::strtoull(p, &after, 10);
    if (*after || last < start)
        return false;
    end = std::min(last + 1, size);
    return true;
}
} // namespace ps5_transfer
