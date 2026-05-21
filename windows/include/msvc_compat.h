#ifndef NEK_WINDOWS_MSVC_COMPAT_H
#define NEK_WINDOWS_MSVC_COMPAT_H

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <BaseTsd.h>

#ifndef _SSIZE_T_DEFINED
typedef SSIZE_T ssize_t;
#define _SSIZE_T_DEFINED
#endif

#ifndef _MODE_T_DEFINED
typedef int mode_t;
#define _MODE_T_DEFINED
#endif

#ifndef mkdir
#define mkdir(path, mode) _mkdir(path)
#endif

#ifndef chdir
#define chdir(path) _chdir(path)
#endif

#ifndef getcwd
#define getcwd(buffer, size) _getcwd(buffer, size)
#endif

#ifndef access
#define access(path, mode) _access(path, mode)
#endif

#ifndef strdup
#define strdup _strdup
#endif
#endif

#endif
