#!/usr/bin/env python3
"""Exercise the real driver decision functions with a deterministic QTEE stub.

Pass the fully patched fpc1553.c. The stub records any finger-lift wait, so a
successful match must be observable without simulating removal of the finger.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()


def function(name):
    start = source.index("static gint\n" + name + " (")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


header = r'''
#include <glib.h>
#include <errno.h>
#define FPC1553_RESULT_RETRY 99
#define FP_DEVICE_RETRY_GENERAL 1
#define FP_FINGER_UNKNOWN 0
#define g_object_ref(p) (p)
typedef struct { guint32 fid; const char *user; } FpPrint;
struct fpc_identify_stats { int unused; };
struct fpc_index_entry { guint32 gid, fid; const char *user_id; };
typedef struct {
  struct { size_t count; struct fpc_index_entry *entries; } index;
  void *device;
} Fpc1553State;
typedef struct {
  FpPrint *input_print, *match_print, *scan_print;
  GPtrArray *gallery;
  GError *retry_error;
  gboolean matched;
} Fpc1553TaskData;
static int waits, scans, backend_result;
static guint32 scanned_fid = 7;
static FpPrint scan;
static guint32 gid_for_user_id(const char *user) { return g_str_hash(user); }
static int extract_print_key(FpPrint *p, guint32 *fid, gchar **user) {
  *fid=p->fid; *user=g_strdup(p->user); return 0;
}
static int run_one_identify(Fpc1553State *s, const char *u, guint32 *fid,
                           struct fpc_identify_stats *stats) {
  scans++; *fid=scanned_fid; return backend_result;
}
static int wait_for_finger_lift(Fpc1553State *s, gboolean wet, gboolean sleep) {
  waits++; return 0;
}
static GError *fpi_device_retry_new(int code) {
  return g_error_new_literal(g_quark_from_static_string("retry"),code,"retry");
}
static const struct fpc_index_entry *find_index_entry(Fpc1553State *s,
    guint32 gid, guint32 fid, const char *u) {
  for (size_t i=0;i<s->index.count;i++) {
    const struct fpc_index_entry *e=&s->index.entries[i];
    if(e->gid==gid && e->fid==fid && !g_strcmp0(e->user_id,u)) return e;
  }
  return NULL;
}
static FpPrint *print_from_entry(void *dev, const struct fpc_index_entry *e) {
  scan=(FpPrint){e->fid,e->user_id}; return &scan;
}
static FpPrint *print_from_key(void *dev, guint32 fid, int finger, const char *u) {
  scan.fid=fid; return &scan;
}
static gboolean set_identify_scan_print(Fpc1553State *s,Fpc1553TaskData *d,
    guint32 gid,guint32 fid,const char *u) {
  const struct fpc_index_entry *e=find_index_entry(s,gid,fid,u);
  if(e) d->scan_print=print_from_entry(s->device,e);
  return e!=NULL;
}
'''
main = r'''
int main(void) {
  FpPrint enrolled={7,"omarchy"}, wrong_user={7,"other"};
  struct fpc_index_entry entry={gid_for_user_id("omarchy"),7,"omarchy"};
  Fpc1553State state={.index={1,&entry}};
  Fpc1553TaskData data={.input_print=&enrolled};
  g_assert_cmpint(run_verify(&state,&data),==,0);
  g_assert_true(data.matched); g_assert_cmpint(waits,==,0);

  data=(Fpc1553TaskData){.input_print=&enrolled}; scanned_fid=8;
  g_assert_cmpint(run_verify(&state,&data),==,0);
  g_assert_false(data.matched); g_assert_cmpint(waits,==,1);

  waits=0; scanned_fid=7; state.index.count=0;
  data=(Fpc1553TaskData){.input_print=&enrolled};
  g_assert_cmpint(run_verify(&state,&data),==,0);
  g_assert_false(data.matched); g_assert_cmpint(waits,==,1);
  state.index.count=1;

  waits=0; backend_result=FPC1553_RESULT_RETRY;
  data=(Fpc1553TaskData){.input_print=&enrolled};
  g_assert_cmpint(run_verify(&state,&data),==,0);
  g_assert_false(data.matched); g_assert_nonnull(data.retry_error);
  g_assert_cmpint(waits,==,1); g_clear_error(&data.retry_error);

  waits=0; backend_result=-EIO;
  data=(Fpc1553TaskData){.input_print=&enrolled};
  g_assert_cmpint(run_verify(&state,&data),==,-EIO);
  g_assert_false(data.matched); g_assert_cmpint(waits,==,0);

  backend_result=0; GPtrArray *gallery=g_ptr_array_new();
  g_ptr_array_add(gallery,&enrolled);
  data=(Fpc1553TaskData){.gallery=gallery};
  g_assert_cmpint(run_identify(&state,&data),==,0);
  g_assert_true(data.matched); g_assert_cmpint(waits,==,0);

  g_ptr_array_index(gallery,0)=&wrong_user; waits=0;
  scanned_fid=0; data=(Fpc1553TaskData){.gallery=gallery};
  g_assert_cmpint(run_identify(&state,&data),==,0);
  g_assert_false(data.matched); g_assert_cmpint(waits,==,1);

  g_ptr_array_set_size(gallery,0); waits=0; scanned_fid=7;
  data=(Fpc1553TaskData){.gallery=gallery};
  g_assert_cmpint(run_identify(&state,&data),==,0);
  g_assert_nonnull(data.scan_print); g_assert_cmpint(waits,==,0);
  g_ptr_array_unref(gallery);
  g_print("PASS: successful verify/identify returns before lift; mismatch, unknown, retry and errors cannot match\n");
}
'''
with tempfile.TemporaryDirectory() as tmp:
    c = Path(tmp) / "driver-test.c"
    binary = Path(tmp) / "driver-test"
    c.write_text(header + function("run_verify") + function("run_identify") + main)
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "glib-2.0"], text=True))
    subprocess.run([os.environ.get("CC", "cc"), "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", str(c), "-o", str(binary), *flags], check=True)
    subprocess.run([str(binary)], check=True)
