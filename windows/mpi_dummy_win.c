#include <string.h>

#include "mpi.h"

static size_t mpi_type_size(MPI_Datatype datatype)
{
  switch (datatype) {
    case MPI_BYTE:
    case MPI_CHAR:
      return 1;
    case MPI_LONG_LONG_INT:
      return sizeof(long long);
    case MPI_DOUBLE:
      return sizeof(double);
    case MPI_INT:
    default:
      return sizeof(int);
  }
}

MPI_Comm MPI_Comm_f2c(MPI_Fint comm)
{
  return comm;
}

MPI_Fint MPI_Comm_c2f(MPI_Comm comm)
{
  return comm;
}

int MPI_Comm_size(MPI_Comm comm, int *size)
{
  (void)comm;
  *size = 1;
  return MPI_SUCCESS;
}

int MPI_Comm_rank(MPI_Comm comm, int *rank)
{
  (void)comm;
  *rank = 0;
  return MPI_SUCCESS;
}

int MPI_Comm_split_type(MPI_Comm comm, int split_type, int key, MPI_Info info, MPI_Comm *newcomm)
{
  (void)split_type;
  (void)key;
  (void)info;
  *newcomm = comm;
  return MPI_SUCCESS;
}

int MPI_Comm_split(MPI_Comm comm, int color, int key, MPI_Comm *newcomm)
{
  (void)key;
  *newcomm = (color == MPI_UNDEFINED) ? MPI_COMM_NULL : comm;
  return MPI_SUCCESS;
}

int MPI_Comm_free(MPI_Comm *comm)
{
  *comm = MPI_COMM_NULL;
  return MPI_SUCCESS;
}

int MPI_Bcast(void *buffer, int count, MPI_Datatype datatype, int root, MPI_Comm comm)
{
  (void)buffer;
  (void)count;
  (void)datatype;
  (void)root;
  (void)comm;
  return MPI_SUCCESS;
}

int MPI_Allreduce(const void *sendbuf, void *recvbuf, int count, MPI_Datatype datatype, MPI_Op op, MPI_Comm comm)
{
  (void)op;
  (void)comm;
  if (sendbuf != MPI_IN_PLACE && sendbuf != recvbuf) {
    memcpy(recvbuf, sendbuf, (size_t)count * mpi_type_size(datatype));
  }
  return MPI_SUCCESS;
}

int MPI_Info_create(MPI_Info *info)
{
  *info = 1;
  return MPI_SUCCESS;
}

int MPI_Info_set(MPI_Info info, const char *key, const char *value)
{
  (void)info;
  (void)key;
  (void)value;
  return MPI_SUCCESS;
}

int MPI_Info_free(MPI_Info *info)
{
  *info = MPI_INFO_NULL;
  return MPI_SUCCESS;
}

int MPI_File_open(MPI_Comm comm, const char *filename, int amode, MPI_Info info, MPI_File *fh)
{
  (void)comm;
  (void)filename;
  (void)amode;
  (void)info;
  *fh = 0;
  return MPI_ERR_OTHER;
}

int MPI_File_set_view(MPI_File fh, long long offset, MPI_Datatype etype, MPI_Datatype filetype, const char *datarep, MPI_Info info)
{
  (void)fh;
  (void)offset;
  (void)etype;
  (void)filetype;
  (void)datarep;
  (void)info;
  return MPI_ERR_OTHER;
}

int MPI_File_read_all(MPI_File fh, void *buf, long long count, MPI_Datatype datatype, MPI_Status *status)
{
  (void)fh;
  (void)buf;
  (void)count;
  (void)datatype;
  (void)status;
  return MPI_ERR_OTHER;
}

int MPI_File_write_all(MPI_File fh, const void *buf, long long count, MPI_Datatype datatype, MPI_Status *status)
{
  (void)fh;
  (void)buf;
  (void)count;
  (void)datatype;
  (void)status;
  return MPI_ERR_OTHER;
}

int MPI_File_close(MPI_File *fh)
{
  *fh = 0;
  return MPI_SUCCESS;
}
