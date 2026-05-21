#ifndef NEK_WINDOWS_MPI_DUMMY_H
#define NEK_WINDOWS_MPI_DUMMY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef int MPI_Comm;
typedef int MPI_Datatype;
typedef int MPI_File;
typedef int MPI_Info;
typedef int MPI_Op;
typedef int MPI_Fint;
typedef int MPI_Status;

#define MPI_COMM_NULL 0
#define MPI_COMM_WORLD 1
#define MPI_COMM_TYPE_SHARED 1
#define MPI_INFO_NULL 0
#define MPI_FILE_NULL 0
#define MPI_UNDEFINED (-32766)
#define MPI_SUCCESS 0
#define MPI_ERR_OTHER 17
#define MPI_MAX_INFO_VAL 255

#define MPI_INT 1
#define MPI_INTEGER 1
#define MPI_BYTE 2
#define MPI_CHAR 3
#define MPI_LONG_LONG_INT 4
#define MPI_DOUBLE 5
#define MPI_DOUBLE_PRECISION 5

#define MPI_MAX 1
#define MPI_MIN 2
#define MPI_SUM 3
#define MPI_PROD 4

#define MPI_MODE_RDONLY 2
#define MPI_MODE_WRONLY 4

#define MPI_IN_PLACE ((void *)1)
#define MPI_STATUS_IGNORE ((MPI_Status *)0)

MPI_Comm MPI_Comm_f2c(MPI_Fint comm);
MPI_Fint MPI_Comm_c2f(MPI_Comm comm);
int MPI_Comm_size(MPI_Comm comm, int *size);
int MPI_Comm_rank(MPI_Comm comm, int *rank);
int MPI_Comm_split_type(MPI_Comm comm, int split_type, int key, MPI_Info info, MPI_Comm *newcomm);
int MPI_Comm_split(MPI_Comm comm, int color, int key, MPI_Comm *newcomm);
int MPI_Comm_free(MPI_Comm *comm);
int MPI_Bcast(void *buffer, int count, MPI_Datatype datatype, int root, MPI_Comm comm);
int MPI_Allreduce(const void *sendbuf, void *recvbuf, int count, MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int MPI_Info_create(MPI_Info *info);
int MPI_Info_set(MPI_Info info, const char *key, const char *value);
int MPI_Info_free(MPI_Info *info);
int MPI_File_open(MPI_Comm comm, const char *filename, int amode, MPI_Info info, MPI_File *fh);
int MPI_File_set_view(MPI_File fh, long long offset, MPI_Datatype etype, MPI_Datatype filetype, const char *datarep, MPI_Info info);
int MPI_File_read_all(MPI_File fh, void *buf, long long count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_all(MPI_File fh, const void *buf, long long count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_close(MPI_File *fh);

#ifdef __cplusplus
}
#endif

#endif
