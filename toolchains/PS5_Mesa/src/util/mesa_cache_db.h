/*
 * Copyright © 2022 Collabora, Ltd.
 *
 * Based on Fossilize DB:
 * Copyright © 2020 Valve Corporation
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef MESA_CACHE_DB_H
#define MESA_CACHE_DB_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "detect_os.h"
#include "simple_mtx.h"

#ifdef __cplusplus
extern "C" {
#endif

struct mesa_cache_db_file {
   FILE *file;
   char *path;
   off_t offset;
   uint64_t uuid;
};

struct mesa_cache_db {
   struct hash_table_u64 *index_db;
   struct mesa_cache_db_file cache;
   struct mesa_cache_db_file index;
   uint64_t max_cache_size;
   simple_mtx_t flock_mtx;
   void *mem_ctx;
   uint64_t uuid;
   bool alive;
   /* Opened by mesa_cache_db_open_exclusive: this process alone uses the
    * files, which stay open and locked, and memory holds the database. */
   bool owned;
   /* An owned database's locks, on descriptors of their own, so that the
    * streams can be reopened without letting go. */
   int lock_fds[2];
   /* Access times read hits changed in memory but not yet in the index file. */
   unsigned dirty_times;
};

#if DETECT_OS_WINDOWS == 0
bool
mesa_cache_db_open(struct mesa_cache_db *db, const char *cache_path);

/* For a process that alone uses the database: fails when another holds it. */
bool
mesa_cache_db_open_exclusive(struct mesa_cache_db *db, const char *cache_path);

void
mesa_cache_db_close(struct mesa_cache_db *db);

void
mesa_cache_db_set_size_limit(struct mesa_cache_db *db,
                             uint64_t max_cache_size);

unsigned int
mesa_cache_db_file_entry_size(void);

void *
mesa_cache_db_read_entry(struct mesa_cache_db *db,
                         const uint8_t *cache_key_160bit,
                         size_t *size);

bool
mesa_cache_db_entry_write(struct mesa_cache_db *db,
                          const uint8_t *cache_key_160bit,
                          const void *blob, size_t blob_size);

bool
mesa_cache_db_entry_remove(struct mesa_cache_db *db,
                           const uint8_t *cache_key_160bit);

bool
mesa_db_wipe_path(const char *cache_path);

bool
mesa_cache_db_has_space(struct mesa_cache_db *db, size_t blob_size);

double
mesa_cache_db_eviction_score(struct mesa_cache_db *db);
#else
static inline bool
mesa_cache_db_open(struct mesa_cache_db *db, const char *cache_path)
{
   return false;
}

static inline bool
mesa_cache_db_open_exclusive(struct mesa_cache_db *db, const char *cache_path)
{
   return false;
}

static inline void
mesa_cache_db_close(struct mesa_cache_db *db)
{
}

static inline void
mesa_cache_db_set_size_limit(struct mesa_cache_db *db,
                             uint64_t max_cache_size)
{
}

static inline unsigned int
mesa_cache_db_file_entry_size(void)
{
   return 0;
}

static inline void *
mesa_cache_db_read_entry(struct mesa_cache_db *db,
                         const uint8_t *cache_key_160bit,
                         size_t *size)
{
   return NULL;
}

static inline bool
mesa_cache_db_entry_write(struct mesa_cache_db *db,
                          const uint8_t *cache_key_160bit,
                          const void *blob, size_t blob_size)
{
   return false;
}

static inline bool
mesa_cache_db_entry_remove(struct mesa_cache_db *db,
                           const uint8_t *cache_key_160bit)
{
   return false;
}

static inline bool
mesa_db_wipe_path(const char *cache_path)
{
   return false;
}

static inline bool
mesa_cache_db_has_space(struct mesa_cache_db *db, size_t blob_size)
{
   return false;
}

static inline double
mesa_cache_db_eviction_score(struct mesa_cache_db *db)
{
   return 0;
}
#endif /* DETECT_OS_WINDOWS */

#ifdef __cplusplus
}
#endif

#endif /* MESA_CACHE_DB_H */
