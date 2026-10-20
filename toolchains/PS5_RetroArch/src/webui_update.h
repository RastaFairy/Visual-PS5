/* Copyright (C) 2026 Mihawk; SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once
#include <string>
namespace ps5_update
{
struct Status
{
    std::string state, message, tag;
    unsigned long long received = 0;
};
void initialize(const std::string &root);
Status status();
bool download(const std::string &tag);
bool request_install();
bool exit_requested();
void stop();
bool install();
// Shared by the worker and the host verification harness.
bool prepare(const std::string &root, const std::string &zip, const std::string &sha256);
bool recover(const std::string &root);
} // namespace ps5_update
