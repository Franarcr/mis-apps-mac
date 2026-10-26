#ifndef CARCHIVE_H
#define CARCHIVE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

// Declaraciones mínimas de libarchive. macOS incluye la biblioteca (/usr/lib/libarchive.2.dylib),
// pero no sus cabeceras, así que aquí se declaran solo las funciones que usa la app.
struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

// Lectura
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_open_filenames(struct archive *, const char **filenames, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *buffer, size_t length);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_format_name(struct archive *);
int64_t archive_filter_bytes(struct archive *, int filter);

// Escritura
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_set_options(struct archive *, const char *options);
int archive_write_set_passphrase(struct archive *, const char *);
int archive_write_open_filename(struct archive *, const char *filename);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

const char *archive_error_string(struct archive *);

// Entradas
struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
void archive_entry_set_size(struct archive_entry *, int64_t);
time_t archive_entry_mtime(struct archive_entry *);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
void archive_entry_set_perm(struct archive_entry *, mode_t);
mode_t archive_entry_perm(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

// Ayudas (CArchive.c): tipo de entrada sin depender de las macros AE_IF*.
int ca_entry_is_file(struct archive_entry *);
int ca_entry_is_directory(struct archive_entry *);
void ca_entry_set_file(struct archive_entry *);
void ca_entry_set_directory(struct archive_entry *);

#endif
