/* Copyright (C) 2026 Mihawk; SPDX-License-Identifier: GPL-3.0-or-later */
/* A small JSON reader for the scraper's sources (ScreenScraper answers in JSON): values
 * are read whole into a tree, and dump() writes one back. Malformed input reads as null. */
#pragma once
#include <cstdio>
#include <cstdlib>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace ps5_scraper
{
struct Json
{
    enum Kind
    {
        null,
        boolean,
        number,
        string,
        array,
        object
    } kind = null;
    bool flag = false;
    double value = 0;
    std::string text;
    std::vector<Json> items;
    std::map<std::string, Json> fields;

    /* A field, or a null value when there is none. */
    const Json &operator[](const std::string &key) const
    {
        static const Json none;
        auto it = fields.find(key);
        return it == fields.end() ? none : it->second;
    }
    /* A string, or a number written as text ("" for anything else). */
    std::string str() const
    {
        if (kind == string)
            return text;
        if (kind == number)
        {
            char out[32];
            std::snprintf(out, sizeof out, "%.15g", value);
            return out;
        }
        return "";
    }

    /* The value as JSON text, for files the WebUI edits (RetroArch's playlists): fields
     * come out in name order, which RetroArch's reader does not mind. */
    static Json of(const std::string &value)
    {
        Json out;
        out.kind = string;
        out.text = value;
        return out;
    }
    std::string dump() const
    {
        switch (kind)
        {
        case boolean:
            return flag ? "true" : "false";
        case number:
            return str();
        case string:
        {
            std::string out = "\"";
            for (unsigned char c : text)
                if (c == '"' || c == '\\')
                    out += '\\', out += char(c);
                else if (c < 0x20)
                {
                    char escaped[8];
                    std::snprintf(escaped, sizeof escaped, "\\u%04x", c);
                    out += escaped;
                }
                else
                    out += char(c);
            return out + '"';
        }
        case array:
        {
            std::string out = "[";
            for (const auto &item : items)
                out += (out.size() > 1 ? "," : "") + item.dump();
            return out + ']';
        }
        case object:
        {
            std::string out = "{";
            for (const auto &field : fields)
                out += (out.size() > 1 ? "," : "") + of(field.first).dump() + ':' +
                       field.second.dump();
            return out + '}';
        }
        default:
            return "null";
        }
    }

    static Json parse(const std::string &input)
    {
        size_t at = 0;
        Json out;
        if (!read(input, at, out, 0))
            return Json();
        return out;
    }

  private:
    static void space(const std::string &s, size_t &at)
    {
        while (at < s.size() && (s[at] == ' ' || s[at] == '\t' || s[at] == '\n' || s[at] == '\r'))
            ++at;
    }
    static void utf8(std::string &out, unsigned code)
    {
        if (code < 0x80)
            out += char(code);
        else if (code < 0x800)
            out += char(0xC0 | code >> 6), out += char(0x80 | (code & 0x3F));
        else if (code < 0x10000)
            out += char(0xE0 | code >> 12), out += char(0x80 | (code >> 6 & 0x3F)),
                out += char(0x80 | (code & 0x3F));
        else
            out += char(0xF0 | code >> 18), out += char(0x80 | (code >> 12 & 0x3F)),
                out += char(0x80 | (code >> 6 & 0x3F)), out += char(0x80 | (code & 0x3F));
    }
    static bool read_string(const std::string &s, size_t &at, std::string &out)
    {
        if (at >= s.size() || s[at] != '"')
            return false;
        ++at;
        while (at < s.size() && s[at] != '"')
        {
            char c = s[at++];
            if (c != '\\')
            {
                out += c;
                continue;
            }
            if (at >= s.size())
                return false;
            c = s[at++];
            switch (c)
            {
            case 'n':
                out += '\n';
                break;
            case 't':
                out += '\t';
                break;
            case 'r':
                out += '\r';
                break;
            case 'b':
                out += '\b';
                break;
            case 'f':
                out += '\f';
                break;
            case 'u':
            {
                if (at + 4 > s.size())
                    return false;
                unsigned code = unsigned(std::strtoul(s.substr(at, 4).c_str(), nullptr, 16));
                at += 4;
                /* A surrogate pair is one character. */
                if (code >= 0xD800 && code < 0xDC00 && at + 6 <= s.size() && s[at] == '\\' &&
                    s[at + 1] == 'u')
                {
                    const unsigned low =
                        unsigned(std::strtoul(s.substr(at + 2, 4).c_str(), nullptr, 16));
                    if (low >= 0xDC00 && low < 0xE000)
                    {
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                        at += 6;
                    }
                }
                utf8(out, code);
                break;
            }
            default:
                out += c; /* \" \\ \/ */
            }
        }
        if (at >= s.size())
            return false;
        ++at;
        return true;
    }
    static bool read(const std::string &s, size_t &at, Json &out, int depth)
    {
        if (depth > 64)
            return false;
        space(s, at);
        if (at >= s.size())
            return false;
        const char c = s[at];
        if (c == '{')
        {
            out.kind = object;
            ++at;
            space(s, at);
            if (at < s.size() && s[at] == '}')
                return ++at, true;
            for (;;)
            {
                std::string key;
                space(s, at);
                if (!read_string(s, at, key))
                    return false;
                space(s, at);
                if (at >= s.size() || s[at++] != ':')
                    return false;
                if (!read(s, at, out.fields[key], depth + 1))
                    return false;
                space(s, at);
                if (at < s.size() && s[at] == ',')
                {
                    ++at;
                    continue;
                }
                return at < s.size() && s[at++] == '}';
            }
        }
        if (c == '[')
        {
            out.kind = array;
            ++at;
            space(s, at);
            if (at < s.size() && s[at] == ']')
                return ++at, true;
            for (;;)
            {
                out.items.emplace_back();
                if (!read(s, at, out.items.back(), depth + 1))
                    return false;
                space(s, at);
                if (at < s.size() && s[at] == ',')
                {
                    ++at;
                    continue;
                }
                return at < s.size() && s[at++] == ']';
            }
        }
        if (c == '"')
        {
            out.kind = string;
            return read_string(s, at, out.text);
        }
        if (s.compare(at, 4, "true") == 0)
            return out.kind = boolean, out.flag = true, at += 4, true;
        if (s.compare(at, 5, "false") == 0)
            return out.kind = boolean, at += 5, true;
        if (s.compare(at, 4, "null") == 0)
            return at += 4, true;
        char *end = nullptr;
        out.value = std::strtod(s.c_str() + at, &end);
        if (end == s.c_str() + at)
            return false;
        out.kind = number;
        at = size_t(end - s.c_str());
        return true;
    }
};
} // namespace ps5_scraper
