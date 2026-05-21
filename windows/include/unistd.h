#ifndef NEK_WINDOWS_UNISTD_H
#define NEK_WINDOWS_UNISTD_H

#include <direct.h>
#include <io.h>
#include <BaseTsd.h>

#ifndef _SSIZE_T_DEFINED
typedef SSIZE_T ssize_t;
#define _SSIZE_T_DEFINED
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

#endif
