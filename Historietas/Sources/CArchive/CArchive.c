#include "CArchive.h"

mode_t archive_entry_filetype(struct archive_entry *);

int ca_entry_is_file(struct archive_entry *entry) {
    return archive_entry_filetype(entry) == 0100000; // AE_IFREG
}
