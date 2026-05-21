#include <mpi.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "gslib.h"
#include "name.h"


#define READ 0
#define WRITE 1
#define CB_BUFFER_SIZE (2<<23)

#define NEKIO_RDERR_COUNT 1
#define NEKIO_RDERR_WRONL 2
#define NEKIO_RDERR_NONFL 3
#define NEKIO_RDERR_MPISV 4
#define NEKIO_RDERR_MPIRA 5
#define NEKIO_RDERR_ACCMD 6
#define NEKIO_RDERR_OVRLP 7
#define NEKIO_RDERR_CREAD 8
#define NEKIO_RDERR_GTPOS 8
#define NEKIO_RDERR_FSEEK 9
#define NEKIO_RDERR_USRBUF 10

#define NEKIO_WRERR_COUNT 1
#define NEKIO_WRERR_RDONL 2
#define NEKIO_WRERR_NONFL 3
#define NEKIO_WRERR_MPISV 4
#define NEKIO_WRERR_MPIWA 5
#define NEKIO_WRERR_NSUPP 6
#define NEKIO_WRERR_CWRITE 7

typedef struct NEK_File_handle {
  char *name;
  int mpiio;
  int agg_id;
  int mode;
  struct comm *comm;

  MPI_File *mpifh;
  MPI_Info info;

  int agg_rank;
  struct comm *aggcomm;
  struct crystal *cr;

  FILE *file;
  struct array *agg;
  struct array *agg2c;
} nekfh;

typedef struct file_block {
  uint proc;
  long long int offset;
  long long int count;
  char buf[CB_BUFFER_SIZE];
} fb;

typedef struct aggregator_child {
  uint proc;
  long long int start;
  long long int end;
} aggc;

static int handle_n = 0;
static int handle_max = 0;
static nekfh **fhandle_arr = 0;
static char fread_buffer[CB_BUFFER_SIZE];

static int nek_path_separator(char c) {
  return c == '/' || c == '\\';
}

static int nek_make_directory(const char *path) {
  if (!path || !path[0]) {
    return 0;
  }
  if (mkdir(path, 0755) == 0 || errno == EEXIST) {
    return 0;
  }
  return 1;
}

static int nek_make_parent_dirs(const char *path) {
  size_t i;
  size_t len;
  char *dirname;

  if (!path) {
    return 1;
  }

  len = strlen(path);
  dirname = (char *)malloc(len + 1);
  if (!dirname) {
    return 1;
  }
  memcpy(dirname, path, len + 1);

  for (i = 0; i < len; ++i) {
    char save;
    if (!nek_path_separator(dirname[i])) {
      continue;
    }
    if (i == 0 || (i == 1 && nek_path_separator(dirname[0])) ||
        (i == 2 && dirname[1] == ':')) {
      continue;
    }

    save = dirname[i];
    dirname[i] = '\0';
    if (nek_make_directory(dirname)) {
      dirname[i] = save;
      free(dirname);
      return 1;
    }
    dirname[i] = save;
  }

  free(dirname);
  return 0;
}

static int nek_file_seek(FILE *file, long long int offset) {
#ifdef _WIN32
  return _fseeki64(file, offset, SEEK_SET);
#else
  return fseek(file, (long)offset, SEEK_SET);
#endif
}


int NEK_File_open(const MPI_Comm comm_in, void *handle, char *filename, int amode,
                  int ifmpiio, int cb_nodes) {
  int rank;

  nekfh *nek_fh = (nekfh *)handle;
  nek_fh->name = NULL;
  nek_fh->mpifh = NULL;
  nek_fh->info = MPI_INFO_NULL;
  nek_fh->file = NULL;

  nek_fh->name = (char *)malloc(strlen(filename) + 1);
  if (!nek_fh->name) {
    return 1;
  }
  strcpy(nek_fh->name, filename);

  int single_proc = 0;
  if(comm_in == MPI_COMM_NULL) { 
    single_proc = 1; 
  } else {
    int size;
    MPI_Comm_size(comm_in, &size);
    if(size == 1) single_proc = 1;
  }

  nek_fh->comm = NULL;
  nek_fh->aggcomm = NULL;
  nek_fh->cr = NULL;
  nek_fh->agg = NULL;
  nek_fh->agg2c = NULL;

  if(single_proc) {

    ifmpiio = 0;
    cb_nodes = 1;
    rank = 0;

  } else {

    nek_fh->comm = (struct comm*) malloc(sizeof(struct comm));
    comm_init(nek_fh->comm, comm_in);
    rank = nek_fh->comm->id;

  }


  if (!ifmpiio && !single_proc) {

    // map aggregator to compute nodes 
    {
      MPI_Comm shmcomm;
      MPI_Comm_split_type(nek_fh->comm->c, MPI_COMM_TYPE_SHARED,
                          nek_fh->comm->id, MPI_INFO_NULL, &shmcomm);

      int shmrank;
      MPI_Comm_rank(shmcomm, &shmrank);
      int color = MPI_UNDEFINED; 
      if(shmrank == 0) color = 1;      

      int num_nodes; 
      int rank_node;
      MPI_Comm nodecomm;
      MPI_Comm_split(nek_fh->comm->c, color, nek_fh->comm->id, &nodecomm);
      if(nodecomm != MPI_COMM_NULL) {
        MPI_Comm_size(nodecomm, &num_nodes);
        MPI_Comm_rank(nodecomm, &rank_node);
      }
      if(nodecomm != MPI_COMM_NULL) MPI_Comm_free(&nodecomm);

      MPI_Bcast(&num_nodes, 1, MPI_INT, 0, shmcomm);
      MPI_Bcast(&rank_node, 1, MPI_INT, 0, shmcomm);

      MPI_Comm_free(&shmcomm);

      if(cb_nodes == 0) {
        cb_nodes = num_nodes;
        nek_fh->agg_id = rank_node;
      } else if(cb_nodes == 1) {
        nek_fh->agg_id = 0;
      } else {
        const int _cb_nodes = ceil((double)num_nodes/cb_nodes);
        const int ratio = (_cb_nodes < num_nodes) ? num_nodes/_cb_nodes : 1;
        nek_fh->agg_id = rank_node/ratio; 
      }

#if 0 
      {
        cb_nodes = 2;
        const int _cb_nodes = cb_nodes;
        const int ratio = (_cb_nodes < nek_fh->comm->np) ? nek_fh->comm->np/_cb_nodes : 1;
        nek_fh->agg_id = rank/ratio; 
        printf("cb_nodes %d ratio %d nek_fh->agg_id %d\n", cb_nodes, ratio, nek_fh->agg_id);
      }
#endif

      nek_fh->aggcomm = (struct comm*) malloc(sizeof(struct comm));
      MPI_Comm aggcomm_mpi;
      MPI_Comm_split(nek_fh->comm->c, nek_fh->agg_id, nek_fh->comm->id, &aggcomm_mpi);
      comm_init(nek_fh->aggcomm, aggcomm_mpi);
     
      if (nek_fh->aggcomm->id == 0) nek_fh->agg_rank = rank;
      MPI_Bcast(&nek_fh->agg_rank, 1, MPI_INT, 0, nek_fh->aggcomm->c);
    }

    nek_fh->cr = (struct crystal*) malloc(sizeof(struct crystal));
    crystal_init(nek_fh->cr, nek_fh->aggcomm);

    nek_fh->agg = (struct array*) calloc(1, sizeof(struct array));
    nek_fh->agg2c = (struct array*) calloc(1, sizeof(struct array)); 
  }

  if (ifmpiio) {

    char *value = (char *) malloc((MPI_MAX_INFO_VAL+1)*sizeof(char));
    MPI_Info_create(&nek_fh->info);
    MPI_Info_set(nek_fh->info, "cb_config_list", "*:1");
    sprintf(value, "%d", cb_nodes);
    MPI_Info_set(nek_fh->info, "cb_nodes", value);
    MPI_Info_set(nek_fh->info, "romio_no_indep_rw", "true");
    MPI_Info_set(nek_fh->info, "romio_cb_read", "enable");
    MPI_Info_set(nek_fh->info, "romio_cb_write", "enable");
    sprintf(value, "%d", CB_BUFFER_SIZE);
    MPI_Info_set(nek_fh->info, "cb_buffer_size", value);
    free(value);

    MPI_File *mpi_fh = malloc(sizeof(MPI_File));
    nek_fh->mpiio = 1;
    switch (amode) {
      case READ:
        nek_fh->mode = MPI_MODE_RDONLY;
        break;
      case WRITE:
        nek_fh->mode = MPI_MODE_WRONLY;
        break;
      default:
        nek_fh->mode = MPI_MODE_RDONLY;
    }

    int ferr = MPI_File_open(nek_fh->comm->c, nek_fh->name, nek_fh->mode, nek_fh->info, mpi_fh);
    if (ferr != MPI_SUCCESS) {
      if (rank == 0) {
        printf("Nek_File_open() :: MPI_File_open failure!\n");
      }
      free(mpi_fh);
      free(nek_fh->name);
      nek_fh->name = NULL;
      return 1;
    }
    nek_fh->mpifh = mpi_fh;

  } else {

    nek_fh->mpiio = 0;
    nek_fh->mode = amode;
    char bytemode[4] = {0};
    switch (amode) {
      case READ:
        strncpy(bytemode, "rb", 2);
        break;
      case WRITE:
        strncpy(bytemode, "wb", 2);
        break;
    }

    if (amode == WRITE && nek_make_parent_dirs(nek_fh->name)) {
      if (rank == 0)  printf("Nek_File_open() :: cannot create parent directory for %s\n", nek_fh->name);
      free(nek_fh->name);
      nek_fh->name = NULL;
      return 1;
    }

    nek_fh->file = fopen(nek_fh->name, bytemode);
    if (!nek_fh->file) {
      if (rank == 0)  printf("Nek_File_open() :: cannot open %s\n", nek_fh->name); 
      free(nek_fh->name);
      nek_fh->name = NULL;
      return 1;
    }
  }

  return 0;
}

int NEK_File_read(void *handle, void *buf, long long int count,
                  long long int offset) {
  nekfh *nek_fh = (nekfh *)handle;

  if (count < 0) {
    return NEKIO_RDERR_COUNT;
  }

  if(nek_fh->comm == NULL) {
    size_t retval;
    if (!nek_fh->file) {
      return NEKIO_RDERR_NONFL;
    }
    if (nek_file_seek(nek_fh->file, offset)) {
      return NEKIO_RDERR_FSEEK;
    }
    retval = fread(buf, 1, (size_t)count, nek_fh->file);
    if (retval != (size_t)count || ferror(nek_fh->file)) {
      return NEKIO_RDERR_CREAD;
    }
    return 0;
  }

  int rank = nek_fh->comm->id;

  int ierr = (count < 0);
  MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
  if (ierr) {
    return NEKIO_RDERR_COUNT;
  }

  if (nek_fh->mpiio) {
    ierr = (nek_fh->mode == MPI_MODE_WRONLY);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
    if (ierr) {
      return NEKIO_RDERR_WRONL;
    }

    ierr = (*(nek_fh->mpifh) == MPI_FILE_NULL);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
    if (ierr) {
      return NEKIO_RDERR_NONFL;
    }

    int ferr = MPI_File_set_view(*(nek_fh->mpifh), offset, MPI_BYTE, MPI_BYTE,
                             "native", nek_fh->info);
    ierr = (ferr != MPI_SUCCESS);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
    if (ierr) {
      return NEKIO_RDERR_MPISV;
    }

    ferr = MPI_File_read_all(*(nek_fh->mpifh), buf, count, MPI_CHAR,MPI_STATUS_IGNORE);

    ierr = (ferr != MPI_SUCCESS);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
    if (ierr) {
      return NEKIO_RDERR_MPIRA;
    }

  } else {

    ierr = (!((nek_fh->mode) == READ));
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, nek_fh->comm->c);
    if (ierr) {
      return NEKIO_RDERR_ACCMD;
    }

    const long long int start_p = offset;
    const long long int end_p = start_p + count;

    // Add aggregator childs
    array_reserve(aggc, nek_fh->agg, 1);
    nek_fh->agg->n = 0;
    if(count) {
      aggc *p = nek_fh->agg->ptr;
      p[0].start = start_p;
      p[0].end = end_p;
      p[0].proc = 0; // aggregator rank (always root of aggcomm)
      nek_fh->agg->n = 1;
    }
    sarray_transfer(aggc, nek_fh->agg, proc, 1, nek_fh->cr);
    const int nchilds_agg = nek_fh->agg->n;

    // Determine byte to read for each aggregator
    long long int count_agg;
    MPI_Allreduce(&count, &count_agg, 1, MPI_LONG_LONG_INT, MPI_SUM,
                  nek_fh->aggcomm->c);

    // read + distribute data in chunks from aggreator to consumer
    int num_b = (count_agg + CB_BUFFER_SIZE - 1) / CB_BUFFER_SIZE;
    MPI_Bcast(&num_b, 1, MPI_INT, 0, nek_fh->aggcomm->c);

    long long int chk_sum_userbuf = 0;

    for (int block = 0; block < num_b; ++block) {
      long long int count_b = (block < num_b - 1)
                              ? CB_BUFFER_SIZE
                              : count_agg - block * CB_BUFFER_SIZE;
      MPI_Bcast(&count_b, 1, MPI_LONG_LONG_INT, 0, nek_fh->aggcomm->c);
      long long int start_b = start_p + block * CB_BUFFER_SIZE;
      MPI_Bcast(&start_b, 1, MPI_LONG_LONG_INT, 0, nek_fh->aggcomm->c);
      long long int end_b = start_b + count_b;

      ierr = 0;
      if (rank == nek_fh->agg_rank) {
        ierr = nek_file_seek(nek_fh->file, start_b);
        fread(fread_buffer, 1, count_b, nek_fh->file);
      }
      ierr = (ierr || ferror(nek_fh->file) || feof(nek_fh->file));
      MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX,
                    nek_fh->aggcomm->c);
      if (ierr) {
        return NEKIO_RDERR_CREAD;
      }

      // Distribute chunk to matching childs
      array_reserve(fb, nek_fh->agg2c, nchilds_agg);
      int nr = 0;
      for (int k = 0; k < nchilds_agg; ++k) {
        aggc *child = nek_fh->agg->ptr;

        // chunk overlaps (partly or completely) with child
        if (start_b <= child[k].end && child[k].start <= end_b) {
          const size_t idx_s =
              (child[k].start < start_b) ? start_b : child[k].start;
          const size_t idx_e =
              (child[k].end > end_b) ? end_b : child[k].end;

          fb *s = nek_fh->agg2c->ptr;
          s[nr].proc = child[k].proc;
          s[nr].offset = idx_s;
          s[nr].count = idx_e - idx_s;

          memcpy(s[nr].buf, fread_buffer + idx_s - start_b, idx_e - idx_s);
          nr++;
        }
      }
      nek_fh->agg2c->n = nr;
      sarray_transfer(fb, nek_fh->agg2c, proc, 1, nek_fh->cr);

      // copy back into user buffer
      for (int k = 0; k < nek_fh->agg2c->n; k++) {
        fb *s = nek_fh->agg2c->ptr;
        chk_sum_userbuf += s[k].count;
        const size_t offset = s[k].offset - start_p;
        memcpy((char *)buf + offset, s[k].buf, s[k].count);
      }
    }

    ierr = 0;
    if (chk_sum_userbuf != count) ierr = 1;
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX,
                  nek_fh->comm->c);
    if (ierr) { return NEKIO_RDERR_USRBUF; }
  }
  return 0;
}

int NEK_File_write(void *handle, void *buf, long long int count,
                   long long int offset) {
  int ierr;
  nekfh *nek_fh = (nekfh *)handle;
  struct comm *c = nek_fh->comm;
  MPI_Comm comm = (c == NULL) ? MPI_COMM_NULL : c->c;
  ierr = 0;

  if (c == NULL) {
    size_t retval;
    if (count < 0) {
      return NEKIO_WRERR_COUNT;
    }
    if (nek_fh->mode != WRITE) {
      return NEKIO_WRERR_RDONL;
    }
    if (!nek_fh->file) {
      return NEKIO_WRERR_NONFL;
    }
    if (nek_file_seek(nek_fh->file, offset)) {
      return NEKIO_WRERR_CWRITE;
    }
    retval = fwrite(buf, 1, (size_t)count, nek_fh->file);
    if (retval != (size_t)count || ferror(nek_fh->file)) {
      return NEKIO_WRERR_CWRITE;
    }
    return 0;
  }

  ierr = (count < 0);
  MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, comm);
  if (ierr) {
    return NEKIO_WRERR_COUNT;
  }

  if (nek_fh->mpiio) {
    ierr = (nek_fh->mode == MPI_MODE_RDONLY);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, comm);
    if (ierr) {
      return NEKIO_WRERR_RDONL;
    }

    ierr = (*(nek_fh->mpifh) == MPI_FILE_NULL);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, comm);
    if (ierr) {
      return NEKIO_WRERR_NONFL;
    }

    int ferr = MPI_File_set_view(*(nek_fh->mpifh), offset, MPI_BYTE, MPI_BYTE,
                             "native", nek_fh->info);
    ierr = (ferr != MPI_SUCCESS);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, comm);
    if (ierr) {
      return NEKIO_WRERR_MPISV;
    }

    ferr = MPI_File_write_all(*(nek_fh->mpifh), buf, count, MPI_BYTE,
                              MPI_STATUS_IGNORE);
    ierr = (ferr != MPI_SUCCESS);
    MPI_Allreduce(MPI_IN_PLACE, &ierr, 1, MPI_INT, MPI_MAX, comm);
    if (ierr) {
      return NEKIO_WRERR_MPIWA;
    }

  } else {

    printf("NEK_File_write: no MPI-IO mode currently not supported!");
    exit(1);
  }

  return 0;
}

void NEK_File_close(void *handle, int *ierr) {
  nekfh *nek_fh = (nekfh *)handle;
  int close_error = 0;

  int rank = 0;
  if(nek_fh->comm != NULL)
    rank = nek_fh->comm->id;

  if (nek_fh->mpiio) {

    int ferr = MPI_File_close(nek_fh->mpifh);
    free(nek_fh->mpifh);
    if (ferr != MPI_SUCCESS) {
      if (rank == 0)
        printf("Nek_File_close() :: MPI_File_close failure!\n");

      close_error = 1;
    }

  } else {

    if (!nek_fh->file) {
      close_error = 0;
    } else if (fclose(nek_fh->file)) {
      if (rank == 0)
        printf("Nek_File_close() :: couldn't fclose file\n");

      close_error = 1;
    }

    if(nek_fh->cr) crystal_free(nek_fh->cr);
    if(nek_fh->agg) array_free(nek_fh->agg);
    if(nek_fh->agg2c) array_free(nek_fh->agg2c);
    if(nek_fh->aggcomm) comm_free(nek_fh->aggcomm);
  }

  if(nek_fh->comm) comm_free(nek_fh->comm);

  free(nek_fh->name);
  nek_fh->name = NULL;

  *ierr = close_error;
}

// Fortran wrappers

#define fNEK_File_open FORTRAN_UNPREFIXED(nek_file_open, NEK_FILE_OPEN)
#define fNEK_File_read FORTRAN_UNPREFIXED(nek_file_read, NEK_FILE_READ)
#define fNEK_File_write FORTRAN_UNPREFIXED(nek_file_write, NEK_FILE_WRITE)
#define fNEK_File_close FORTRAN_UNPREFIXED(nek_file_close, NEK_FILE_CLOSE)

void fNEK_File_open(const int *fcomm, char *filename, int *amode, int *ifmpiio,
                    int *cb_nodes, int *handle, int *ierr, int nlen) {
  *ierr = 1;
  comm_ext c = MPI_Comm_f2c(*fcomm);
  if (handle_n == handle_max) {
    handle_max += handle_max / 2 + 1;
    fhandle_arr = trealloc(nekfh *, fhandle_arr, handle_max);
  }
  fhandle_arr[handle_n] = (nekfh *)tmalloc(nekfh, 1);

  char *fname = (char*) calloc((nlen+1), sizeof(char));
  {
    int i;
    strncpy(fname, filename, nlen);
    for (i = nlen - 1; i > 0; i--)
      if (fname[i] != ' ') break;
    fname[i + 1] = '\0';
  }
  *ierr = NEK_File_open(c, fhandle_arr[handle_n], fname, *amode, *ifmpiio,
                        *cb_nodes);
  if (*ierr) {
    free(fhandle_arr[handle_n]);
    fhandle_arr[handle_n] = 0;
    free(fname);
    return;
  }
  *handle = handle_n++;

  free(fname);
}

void fNEK_File_read(int *handle, long long int *count, long long int *offset,
                    void *buf, int *ierr) {
  nekfh *fh = fhandle_arr[*handle];
  *ierr = NEK_File_read(fh, buf, *count, *offset);
}

void fNEK_File_write(int *handle, long long int *count, long long int *offset,
                     void *buf, int *ierr) {
  nekfh *fh = fhandle_arr[*handle];
  *ierr = NEK_File_write(fh, buf, *count, *offset);
}

void fNEK_File_close(int *handle, int *ierr) {
  NEK_File_close(fhandle_arr[*handle], ierr);
  free(fhandle_arr[*handle]);
  fhandle_arr[*handle] = 0;
}
