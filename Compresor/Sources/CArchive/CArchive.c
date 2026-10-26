#include "CArchive.h"

mode_t archive_entry_filetype(struct archive_entry *);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);

#define CA_IFREG 0100000
#define CA_IFDIR 0040000

int ca_entry_is_file(struct archive_entry *entry) { return archive_entry_filetype(entry) == CA_IFREG; }
int ca_entry_is_directory(struct archive_entry *entry) { return archive_entry_filetype(entry) == CA_IFDIR; }
void ca_entry_set_file(struct archive_entry *entry) { archive_entry_set_filetype(entry, CA_IFREG); }
void ca_entry_set_directory(struct archive_entry *entry) { archive_entry_set_filetype(entry, CA_IFDIR); }
