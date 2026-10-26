#ifndef CGRABADOR_H
#define CGRABADOR_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

// Declaraciones mínimas de libarchive. macOS incluye la biblioteca (/usr/lib/libarchive.2.dylib),
// pero no sus cabeceras, así que aquí se declaran solo las funciones que usa la app.
struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_WARN (-20)

struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_read_support_format_zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *buffer, size_t length);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
int64_t archive_filter_bytes(struct archive *, int filter);
int archive_filter_count(struct archive *);
const char *archive_error_string(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);

/// 1 si la entrada es un archivo normal.
int cg_entry_is_file(struct archive_entry *);

/// Recibe por un socket el descriptor que envía `authopen -stdoutpipe` (SCM_RIGHTS). -1 si no llega.
int cg_receive_fd(int socket);

#endif
