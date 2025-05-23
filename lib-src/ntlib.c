/* Utility and Unix shadow routines for GNU Emacs support programs on NT.

Copyright (C) 1994, 2001-2025 Free Software Foundation, Inc.

Author: Geoff Voelker (voelker@cs.washington.edu)
Created: 10-8-94

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#define DEFER_MS_W32_H
#include <config.h>

#include <windows.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <direct.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <errno.h>
#include <ctype.h>
#include <sys/timeb.h>
#include <mbstring.h>
#include <locale.h>

#include <nl_types.h>
#include <langinfo.h>

#include "ntlib.h"

char *sys_ctime (const time_t *);
FILE *sys_fopen (const char *, const char *);
int sys_mkdir (const char *, mode_t);
int sys_chdir (const char *);
int mkostemp (char *, int);
int sys_rename (const char *, const char *);
int sys_open (const char *, int, int);

/* MinGW64 defines _TIMEZONE_DEFINED and defines 'struct timespec' in
   its system headers.  */
#ifndef _TIMEZONE_DEFINED
struct timezone
{
  int		tz_minuteswest;	/* minutes west of Greenwich */
  int		tz_dsttime;	/* type of dst correction */
};
#endif

#define MAXPATHLEN _MAX_PATH

/* Emulate sleep...we could have done this with a define, but that
   would necessitate including windows.h in the files that used it.
   This is much easier.  */
unsigned
sleep (unsigned seconds)
{
  Sleep (seconds * 1000);
  return 0;
}

/* Get the current working directory.  */
char *
getwd (char *dir)
{
  if (GetCurrentDirectory (MAXPATHLEN, dir) > 0)
    return dir;
  return NULL;
}

static HANDLE getppid_parent;
static int    getppid_ppid;

int
getppid (void)
{
  char *ppid;
  DWORD result;

  ppid = getenv ("EM_PARENT_PROCESS_ID");
  if (!ppid)
    {
      printf ("no pid.\n");
      return 0;
    }
  else
    {
      getppid_ppid = atoi (ppid);
    }

  if (!getppid_parent)
    {
      getppid_parent = OpenProcess (SYNCHRONIZE, FALSE, atoi (ppid));
      if (!getppid_parent)
	{
	  printf ("Failed to open handle to parent process: %lu\n",
		 GetLastError ());
	  exit (1);
	}
    }

  result = WaitForSingleObject (getppid_parent, 0);
  switch (result)
    {
    case WAIT_TIMEOUT:
      /* The parent is still alive.  */
      return getppid_ppid;
    case WAIT_OBJECT_0:
      /* The parent is gone.  Return the pid of Unix init (1).  */
      return 1;
    case WAIT_FAILED:
    default:
      printf ("Checking parent status failed: %lu\n", GetLastError ());
      exit (1);
    }
}

char *
getlogin (void)
{
  static char user_name[256];
  DWORD  length = sizeof (user_name);

  if (GetUserName (user_name, &length))
    return user_name;
  return NULL;
}

unsigned
getuid (void)
{
  return 0;
}

unsigned
geteuid (void)
{
  return getuid ();
}

unsigned
getgid (void)
{
  return 0;
}

unsigned
getegid (void)
{
  return 0;
}

int
setuid (unsigned uid)
{
  return 0;
}

int
setregid (unsigned rgid, unsigned gid)
{
  return 0;
}

struct passwd *
getpwuid (unsigned uid)
{
  return NULL;
}

char *
getpass (const char * prompt)
{
  static char input[256];
  HANDLE in;
  HANDLE err;
  DWORD  count;

  in = GetStdHandle (STD_INPUT_HANDLE);
  err = GetStdHandle (STD_ERROR_HANDLE);

  if (in == INVALID_HANDLE_VALUE || err == INVALID_HANDLE_VALUE)
    return NULL;

  if (WriteFile (err, prompt, strlen (prompt), &count, NULL))
    {
      int istty = (GetFileType (in) == FILE_TYPE_CHAR);
      DWORD old_flags;
      int rc;

      if (istty)
	{
	  if (GetConsoleMode (in, &old_flags))
	    SetConsoleMode (in, ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT);
	  else
	    istty = 0;
	}
      rc = ReadFile (in, input, sizeof (input), &count, NULL);
      if (count >= 2 && input[count - 2] == '\r')
	input[count - 2] = '\0';
      else
	{
	  char buf[256];
	  while (ReadFile (in, buf, sizeof (buf), &count, NULL) > 0)
	    if (count >= 2 && buf[count - 2] == '\r')
	      break;
	}
      WriteFile (err, "\r\n", 2, &count, NULL);
      if (istty)
	SetConsoleMode (in, old_flags);
      if (rc)
	return input;
    }

  return NULL;
}

int
fchown (int fd, unsigned uid, unsigned gid)
{
  return 0;
}

FILE *
sys_fopen (const char * path, const char * mode)
{
  return fopen (path, mode);
}

int
sys_chdir (const char * path)
{
  return _chdir (path);
}

int
sys_mkdir (const char * path, mode_t mode)
{
  return _mkdir (path);
}

static FILETIME utc_base_ft;
static long double utc_base;
static int init = 0;

static time_t
convert_time (FILETIME ft, int *time_nsec)
{
  long double ret;

  if (CompareFileTime (&ft, &utc_base_ft) < 0)
    return 0;

  ret = (long double) ft.dwHighDateTime
    * 4096.0L * 1024.0L * 1024.0L + ft.dwLowDateTime;
  ret -= utc_base;
  *time_nsec = (int) fmodl (ret, 1.0e7L) * 100;
  return (time_t) (ret * 1.0e-7L);
}

static int
is_exec (const char * name)
{
  char * p = strrchr (name, '.');
  return
    (p != NULL
     && (stricmp (p, ".exe") == 0 ||
	 stricmp (p, ".com") == 0 ||
	 stricmp (p, ".bat") == 0 ||
	 stricmp (p, ".cmd") == 0));
}

/* We need stat/fsfat below because nt/inc/sys/stat.h defines struct
   stat that is incompatible with the MS run-time libraries.  */
int
stat (const char * path, struct stat * buf)
{
  WIN32_FIND_DATA wfd;
  HANDLE fh;
  int permission;
  int len;
  int rootdir = FALSE;
  char *name = alloca (FILENAME_MAX);

  if (!init)
    {
      /* Determine the delta between 1-Jan-1601 and 1-Jan-1970. */
      SYSTEMTIME st;

      st.wYear = 1970;
      st.wMonth = 1;
      st.wDay = 1;
      st.wHour = 0;
      st.wMinute = 0;
      st.wSecond = 0;
      st.wMilliseconds = 0;

      SystemTimeToFileTime (&st, &utc_base_ft);
      utc_base = (long double) utc_base_ft.dwHighDateTime
	* 4096.0L * 1024.0L * 1024.0L + utc_base_ft.dwLowDateTime;
      init = 1;
    }

  if (path == NULL || buf == NULL || *path == '\0')
    {
      errno = EFAULT;
      return -1;
    }
  if (_mbspbrk (path, "*?|<>\""))
    {
      errno = ENOENT;
      return -1;
    }

  strcpy (name, path);
  /* Remove trailing directory separator, unless name is the root
     directory of a drive in which case ensure there is a trailing
     separator. */
  len = strlen (name);
  rootdir = IS_DIRECTORY_SEP (name[0])
    || (len == 3 && name[1] == ':' && IS_DIRECTORY_SEP (name[2]));
  if (rootdir)
    {
      if (GetDriveType (name) < 2)
	{
	  errno = ENOENT;
	  return -1;
	}
      memset (&wfd, 0, sizeof (wfd));
      wfd.dwFileAttributes = FILE_ATTRIBUTE_DIRECTORY;
      wfd.ftCreationTime = utc_base_ft;
      wfd.ftLastAccessTime = utc_base_ft;
      wfd.ftLastWriteTime = utc_base_ft;
      strcpy (wfd.cFileName, name);
    }
  else
    {
      if (IS_DIRECTORY_SEP (name[len-1]))
	name[len - 1] = 0;

      fh = FindFirstFile (name, &wfd);
      if (fh == INVALID_HANDLE_VALUE)
	{
	  errno = ENOENT;
	  return -1;
	}
      FindClose (fh);
    }
  buf->st_mode = (wfd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ?
    S_IFDIR : S_IFREG;
  buf->st_nlink = 1;
  buf->st_ino = 0;

  if (name[0] && name[1] == ':')
    buf->st_dev = tolower (name[0]) - 'a' + 1;
  else
    buf->st_dev = _getdrive ();
  buf->st_rdev = buf->st_dev;

  buf->st_size = wfd.nFileSizeHigh;
  buf->st_size <<= 32;
  buf->st_size += wfd.nFileSizeLow;

  /* Convert timestamps to Unix format. */
  buf->st_mtime = convert_time (wfd.ftLastWriteTime, &buf->st_mtimensec);
  buf->st_atime = convert_time (wfd.ftLastAccessTime, &buf->st_atimensec);
  if (buf->st_atime == 0)
    {
      buf->st_atime = buf->st_mtime;
      buf->st_atimensec = buf->st_mtimensec;
    }
  buf->st_ctime = convert_time (wfd.ftCreationTime, &buf->st_ctimensec);
  if (buf->st_ctime == 0)
    {
      buf->st_ctime = buf->st_mtime;
      buf->st_ctimensec = buf->st_mtimensec;
    }

  /* determine rwx permissions */
  if (wfd.dwFileAttributes & FILE_ATTRIBUTE_READONLY)
    permission = S_IREAD;
  else
    permission = S_IREAD | S_IWRITE;

  if (wfd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
    permission |= S_IEXEC;
  else if (is_exec (name))
    permission |= S_IEXEC;

  buf->st_mode |= permission | (permission >> 3) | (permission >> 6);

  return 0;
}

int
lstat (const char * path, struct stat * buf)
{
  return stat (path, buf);
}

int
fstat (int desc, struct stat * buf)
{
  HANDLE fh = (HANDLE) _get_osfhandle (desc);
  BY_HANDLE_FILE_INFORMATION info;
  unsigned __int64 fake_inode;
  int permission;

  if (!init)
    {
      /* Determine the delta between 1-Jan-1601 and 1-Jan-1970. */
      SYSTEMTIME st;

      st.wYear = 1970;
      st.wMonth = 1;
      st.wDay = 1;
      st.wHour = 0;
      st.wMinute = 0;
      st.wSecond = 0;
      st.wMilliseconds = 0;

      SystemTimeToFileTime (&st, &utc_base_ft);
      utc_base = (long double) utc_base_ft.dwHighDateTime
	* 4096.0L * 1024.0L * 1024.0L + utc_base_ft.dwLowDateTime;
      init = 1;
    }

  switch (GetFileType (fh) & ~FILE_TYPE_REMOTE)
    {
    case FILE_TYPE_DISK:
      buf->st_mode = S_IFREG;
      if (!GetFileInformationByHandle (fh, &info))
	{
	  errno = EACCES;
	  return -1;
	}
      break;
    case FILE_TYPE_PIPE:
      buf->st_mode = S_IFIFO;
      goto non_disk;
    case FILE_TYPE_CHAR:
    case FILE_TYPE_UNKNOWN:
    default:
      buf->st_mode = S_IFCHR;
    non_disk:
      memset (&info, 0, sizeof (info));
      info.dwFileAttributes = 0;
      info.ftCreationTime = utc_base_ft;
      info.ftLastAccessTime = utc_base_ft;
      info.ftLastWriteTime = utc_base_ft;
    }

  if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
      buf->st_mode = S_IFDIR;

  buf->st_nlink = info.nNumberOfLinks;
  /* Might as well use file index to fake inode values, but this
     is not guaranteed to be unique unless we keep a handle open
     all the time. */
  fake_inode = info.nFileIndexHigh;
  fake_inode <<= 32;
  fake_inode += info.nFileIndexLow;
  buf->st_ino = fake_inode;

  buf->st_dev = info.dwVolumeSerialNumber;
  buf->st_rdev = info.dwVolumeSerialNumber;

  buf->st_size = info.nFileSizeHigh;
  buf->st_size <<= 32;
  buf->st_size += info.nFileSizeLow;

  /* Convert timestamps to Unix format. */
  buf->st_mtime = convert_time (info.ftLastWriteTime, &buf->st_mtimensec);
  buf->st_atime = convert_time (info.ftLastAccessTime, &buf->st_atimensec);
  if (buf->st_atime == 0)
    {
      buf->st_atime = buf->st_mtime;
      buf->st_atimensec = buf->st_mtimensec;
    }
  buf->st_ctime = convert_time (info.ftCreationTime, &buf->st_ctimensec);
  if (buf->st_ctime == 0)
    {
      buf->st_ctime = buf->st_mtime;
      buf->st_ctimensec = buf->st_mtimensec;
    }

  /* determine rwx permissions */
  if (info.dwFileAttributes & FILE_ATTRIBUTE_READONLY)
    permission = S_IREAD;
  else
    permission = S_IREAD | S_IWRITE;

  if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
    permission |= S_IEXEC;

  buf->st_mode |= permission | (permission >> 3) | (permission >> 6);

  return 0;
}

/* On Windows, you cannot rename into an existing file.  */
int
sys_rename (const char *from, const char *to)
{
  int retval = rename (from, to);

  if (retval < 0 && errno == EEXIST)
    {
      if (unlink (to) == 0)
	retval = rename (from, to);
    }
  return retval;
}

int
sys_open (const char * path, int oflag, int mode)
{
  return _open (path, oflag, mode);
}

/* Emulation of nl_langinfo that supports only CODESET.
   Used in Gnulib regex.c.  */
char *
nl_langinfo (nl_item item)
{
  switch (item)
    {
      case CODESET:
	{
	  /* Shamelessly stolen from Gnulib's nl_langinfo.c, modulo
	     CPP directives.  */
	  static char buf[2 + 10 + 1];
	  char const *locale = setlocale (LC_CTYPE, NULL);
	  char *codeset = buf;
	  size_t codesetlen;
	  codeset[0] = '\0';

	  if (locale && locale[0])
	    {
	      /* If the locale name contains an encoding after the
		 dot, return it.  */
	      char *dot = strchr (locale, '.');

	      if (dot)
		{
		  /* Look for the possible @... trailer and remove it,
		     if any.  */
		  char *codeset_start = dot + 1;
		  char const *modifier = strchr (codeset_start, '@');

		  if (! modifier)
		    codeset = codeset_start;
		  else
		    {
		      codesetlen = modifier - codeset_start;
		      if (codesetlen < sizeof buf)
			{
			  codeset = memcpy (buf, codeset_start, codesetlen);
			  codeset[codesetlen] = '\0';
			}
		    }
		}
	    }
	  /* If setlocale is successful, it returns the number of the
	     codepage, as a string.  Otherwise, fall back on Windows
	     API GetACP, which returns the locale's codepage as a
	     number (although this doesn't change according to what
	     the 'setlocale' call specified).  Either way, prepend
	     "CP" to make it a valid codeset name.  */
	  codesetlen = strlen (codeset);
	  if (0 < codesetlen && codesetlen < sizeof buf - 2)
	    memmove (buf + 2, codeset, codesetlen + 1);
	  else
	    sprintf (buf + 2, "%u", GetACP ());
	  codeset = memcpy (buf, "CP", 2);

	  return codeset;
	}
      default:
	return (char *) "";
    }
}
