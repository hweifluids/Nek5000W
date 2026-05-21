#include <direct.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <psapi.h>

#include "name.h"

#define cexit FORTRAN_UNPREFIXED(cexit, CEXIT)
#define print_stack FORTRAN_UNPREFIXED(print_stack, PRINT_STACK)
#define sizeOfLongInt FORTRAN_UNPREFIXED(sizeoflongint, SIZEOFLONGINT)
#define getmaxrss FORTRAN_UNPREFIXED(getmaxrss, GETMAXRSS)
#define set_stdout FORTRAN_UNPREFIXED(set_stdout, SET_STDOUT)
#define cchdir FORTRAN_UNPREFIXED(fchdir, FCHDIR)

float etime(float *elapsed)
{
  static LARGE_INTEGER frequency;
  static LARGE_INTEGER start;
  LARGE_INTEGER now;
  float seconds;

  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&start);
  }

  QueryPerformanceCounter(&now);
  seconds = (float)((double)(now.QuadPart - start.QuadPart) /
                    (double)frequency.QuadPart);
  if (elapsed) {
    elapsed[0] = seconds;
    elapsed[1] = 0.0f;
  }
  return seconds;
}

void cchdir(char *path, int plen)
{
  char *dir = (char *) malloc((plen + 1) * sizeof(char));
  int i;
  strncpy(dir, path, plen);
  for (i = plen - 1; i >= 0; i--) if (dir[i] != ' ') break;
  dir[i + 1] = '\0';

  if (_chdir(dir) != 0) {
    printf("ERROR: Cannot change working directory '%s'!\n", dir);
    exit(1);
  }
  free(dir);
}

void print_stack(void)
{
}

double getmaxrss(void)
{
  PROCESS_MEMORY_COUNTERS counters;
  memset(&counters, 0, sizeof(counters));
  counters.cb = sizeof(counters);
  if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) {
    return (double)counters.PeakWorkingSetSize;
  }
  return 0.0;
}

int sizeOfLongInt(void)
{
  return sizeof(long int);
}

void set_stdout(char *f, int *sid, int flen)
{
  char *logfile = (char *) malloc((flen + 2 + 5 + 1) * sizeof(char));
  int i;
  int redirect = 0;

  strncpy(logfile, f, flen);
  for (i = flen - 1; i >= 0; i--) if (logfile[i] != ' ') break;
  logfile[i + 1] = '\0';

  if (logfile[0] != '\0') {
    redirect = 1;
  } else {
    char *envvar = getenv("NEK_LOGFILE");
    if (envvar) {
      if (*sid >= 0) sprintf(logfile, "s%05d_", *sid);
      strcat(logfile + strlen(logfile), envvar);
      redirect = 1;
    }
  }

  if (redirect) {
    printf("redirecting stdout to %s\n", logfile);
    freopen(logfile, "w+", stdout);
  }
  free(logfile);
}

void cexit(int *ierr)
{
  exit(*ierr);
}
