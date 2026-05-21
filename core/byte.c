#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <math.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef FNAME_H
#define FNAME_H

/*
   FORTRAN naming convention
     default      cpgs_setup, etc.
     -DUPCASE     CPGS_SETUP, etc.
     -DUNDERSCORE cpgs_setup_, etc.
*/

#ifdef UPCASE
#  define FORTRAN_NAME(low,up) up
#else
#ifdef UNDERSCORE
#  define FORTRAN_NAME(low,up) low##_
#else
#  define FORTRAN_NAME(low,up) low
#endif
#endif

#endif

#define byte_reverse     FORTRAN_NAME(byte_reverse,     BYTE_REVERSE    )
#define byte_reverse8    FORTRAN_NAME(byte_reverse8,    BYTE_REVERSE8   )
#define byte_open        FORTRAN_NAME(byte_open,        BYTE_OPEN       )
#define byte_seek        FORTRAN_NAME(byte_seek,        BYTE_SEEK       )
#define byte_close       FORTRAN_NAME(byte_close,       BYTE_CLOSE      )
#define byte_rewind      FORTRAN_NAME(byte_rewind,      BYTE_REWIND     )
#define byte_read        FORTRAN_NAME(byte_read,        BYTE_READ       )
#define byte_write       FORTRAN_NAME(byte_write,       BYTE_WRITE      )
#define get_bytesw_write FORTRAN_NAME(get_bytesw_write, GET_BYTESW_WRITE)
#define set_bytesw_write FORTRAN_NAME(set_bytesw_write, SET_BYTESW_WRITE)

#define READ     1
#define WRITE    2
#define MAX_NAME 132

#define SWAP(a,b)       temp=(a); (a)=(b); (b)=temp;

static FILE *fp=NULL;
static int  flag=0;
static char name[MAX_NAME+1];

int bytesw_write=0;
int bytesw_read=0;

static int byte_path_separator(char c)
{
  return c == '/' || c == '\\';
}

static int byte_make_directory(const char *path)
{
  if (!path || !path[0])
    return 0;

  if (mkdir(path,0755) == 0 || errno == EEXIST)
    return 0;

  return 1;
}

static int byte_make_parent_dirs(const char *path)
{
  int i;
  int len;
  char dirname[MAX_NAME+1];

  if (!path)
    return 1;

  len = (int)strlen(path);
  if (len > MAX_NAME)
    return 1;

  strncpy(dirname,path,MAX_NAME);
  dirname[MAX_NAME] = '\0';

  for (i=0; i<len; i++)
  {
    char save;
    if (!byte_path_separator(dirname[i]))
      continue;
    if (i == 0 || (i == 1 && byte_path_separator(dirname[0])) ||
        (i == 2 && dirname[1] == ':'))
      continue;

    save = dirname[i];
    dirname[i] = '\0';
    if (byte_make_directory(dirname))
    {
      dirname[i] = save;
      return 1;
    }
    dirname[i] = save;
  }

  return 0;
}

static int byte_file_seek(FILE *file, long long offset)
{
#ifdef _WIN32
  return _fseeki64(file, offset, SEEK_SET);
#else
  return fseek(file, (long)offset, SEEK_SET);
#endif
}

/*************************************byte.c***********************************/

#ifdef UNDERSCORE
  void exitt_();
#else
  void exitt();
#endif

void byte_reverse(float *buf, int *nn,int *ierr)
{
  int n;
  char temp, *ptr;

  if (*nn<0)
  {
    printf("byte_reverse() :: n must be positive\n"); 
    *ierr=1;
    return;
  }
  
  for (ptr=(char *)buf,n=*nn; n--; ptr+=4)
  {
     SWAP(ptr[0],ptr[3])
     SWAP(ptr[1],ptr[2])
  }
  *ierr=0;
}

void byte_reverse8(float *buf, int *nn,int *ierr)
{
  int n;
  char temp, *ptr;

  if (*nn<0)
  {
    printf("byte_reverse8() :: n must be positive\n");
    *ierr=1;
    return;
  }
  if(*nn % 2 != 0)
  {
    printf("byte_reverse8() :: n must be multiple of 2\n");
    *ierr=1;
    return;
  }

  for (ptr=(char *)buf,n=*nn,n=n+2; n-=2; ptr+=8)
  {
     SWAP(ptr[0],ptr[7])
     SWAP(ptr[1],ptr[6])
     SWAP(ptr[2],ptr[5])
     SWAP(ptr[3],ptr[4])
  }
  *ierr=0;
}


void byte_open(char *n,int *ierr,int nlen)
{
  int  i;

  if (nlen>MAX_NAME)
  {
    printf("byte_open() :: invalid string length\n"); 
    *ierr=1;
    return;
  }
  strncpy(name,n,nlen);
  for (i=nlen-1; i>0; i--) if (name[i] != ' ') break;
  name[i+1] = '\0';

  if (byte_make_parent_dirs(name))
  {
    printf("byte_open() :: cannot create parent directory for %s\n",name);
    *ierr=1;
    return;
  }

  *ierr=0;
}

void byte_close(int *ierr)
{
  if (!fp) return;

  if (fclose(fp))
  {
    printf("byte_close() :: couldn't fclose file!\n");
    *ierr=1;
    return;
  }

  fp=NULL;
  *ierr=0;
}

void byte_rewind()
{
  if (!fp) return;

  rewind(fp);
}

void byte_seek(int *n,int *ierr)
{
  if (*n<0)
    {printf("byte_seek() :: n must be positive\n"); *ierr=1; return;}

  if (!fp)
  {
     if (!(fp=fopen(name,"rb")))
     {
        printf("%s\n",name);
        printf("byte_seek() :: fopen failure2!\n");
        *ierr=1;
        return;
     }
     flag=READ;
  }

  if (byte_file_seek(fp,(long long)(*n)*sizeof(float)))
  {
    printf("byte_seek() :: fseek failure!\n");
    *ierr=1;
    return;
  }
  *ierr=0;
}




void byte_write(float *buf, int *n,int *ierr)
{
  if (*n<0)
  {
    printf("byte_write() :: n must be positive\n"); 
    *ierr=1;
    return;
  }

  if (!fp)
  {
    if (!(fp=fopen(name,"wb")))
    {
      printf("byte_write() :: fopen failure!\n"); 
      *ierr=1;
      return;
    }
    flag=WRITE;
  }

  if (flag==WRITE)
    {
      if (bytesw_write == 1)
        byte_reverse (buf,n,ierr);
      fwrite(buf,sizeof(float),*n,fp);
    }
  else
  {
      printf("byte_write() :: can't fwrite after freading!\n"); 
      *ierr=1;
      return;
  }
  *ierr=0;
}


void byte_read(float *buf, int *n,int *ierr)
{
  if (*n<0)
    {printf("byte_read() :: n must be positive\n"); *ierr=1; return;}

  if (!fp)
  {
     if (!(fp=fopen(name,"rb")))
     {
        printf("%s\n",name);
        printf("byte_read() :: fopen failure2!\n"); 
        *ierr=1;
        return;
     }
     flag=READ;
  }

  if (flag==READ)
  {
     if (bytesw_read == 1)
        byte_reverse (buf,n,ierr);
     fread(buf,sizeof(float),*n,fp);
     if (ferror(fp))
     {
       printf("ABORT: Error reading %s\n",name);
       *ierr=1;
       return;
     }
     else if (feof(fp))
     {
       printf("ABORT: EOF found while reading %s\n",name);
       *ierr=1;
       return;
     }

  }
  else
  {
     printf("byte_read() :: can't fread after fwriting!\n"); 
     *ierr=1;
     return;
  }
  *ierr=0;
}

void set_bytesw_write (int *pa)
{
    if (*pa != 0)
       bytesw_write = 1;
    else
       bytesw_write = 0;
}

void set_bytesw_read (int *pa)
{
    if (*pa != 0)
       bytesw_read = 1;
    else
       bytesw_read = 0;
}

void get_bytesw_write (int *pa)
{
    *pa = bytesw_write;
}

void get_bytesw_read (int *pa)
{
    *pa = bytesw_read;
}
