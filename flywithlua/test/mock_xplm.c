/*
 * A stand-in for X-Plane's XPLM library, just enough of it to run
 * Cinematic_Views.lua under plain LuaJIT: datarefs, commands that change the
 * view, command handlers, camera control (calling the script's FFI callbacks
 * for real), the user's aircraft file name, a terrain probe and world/local
 * conversion with a movable local origin.
 */
#include <stdio.h>
#include <string.h>

#define MAX_REFS 128
#define MAX_CMDS 32

typedef struct { char name[128]; double value; } Ref;
typedef struct { char name[128]; } Cmd;
typedef struct { float x, y, z, pitch, heading, roll, zoom; } CameraPosition;
typedef int (*CameraControl)(CameraPosition *pos, int losing, void *refcon);
typedef struct {
  int structSize;
  float locationX, locationY, locationZ, normalX, normalY, normalZ, velocityX, velocityY, velocityZ;
  int is_wet;
} ProbeInfo;

static Ref refs[MAX_REFS];
static int nrefs;
static Cmd cmds[MAX_CMDS];
static int ncmds;
static CameraControl cam_cb;
static void *cam_ref;
static int cam_duration;
static CameraPosition cam_pos;
static double ground_y;
static double origin_x, origin_z;      /* local origin offset, in metres east/south */
static char last_cmd[128];
static int cmd_count;
static int probe_count;
static char acf_name[256] = "A320.acf";
static int joy_buttons[3200];
static int joy_token;                 /* stands in for sim/joystick/joystick_button_values */

typedef int (*CommandCallback)(void *cmd, int phase, void *refcon);
typedef struct { void *cmd; CommandCallback cb; int before; void *refcon; int used; } Handler;
static Handler handlers[64];

static Ref *ref_named(const char *name) {
  for (int i = 0; i < nrefs; i++) if (strcmp(refs[i].name, name) == 0) return &refs[i];
  return NULL;
}

/* ---- test controls ---- */
void mock_define(const char *name, double value) {
  Ref *r = ref_named(name);
  if (!r && nrefs < MAX_REFS) { r = &refs[nrefs++]; snprintf(r->name, sizeof r->name, "%s", name); }
  if (r) r->value = value;
}
double mock_get(const char *name) { Ref *r = ref_named(name); return r ? r->value : -99999; }
void mock_define_command(const char *name) {
  if (ncmds < MAX_CMDS) snprintf(cmds[ncmds++].name, sizeof cmds[0].name, "%s", name);
}
void mock_set_ground(double y) { ground_y = y; }
void mock_shift_origin(double dx, double dz) { origin_x += dx; origin_z += dz; }
const char *mock_last_command(void) { return last_cmd; }
int mock_command_count(void) { return cmd_count; }
int mock_probe_count(void) { return probe_count; }
int mock_camera_controlled(void) { return cam_cb != NULL; }
void mock_set_aircraft(const char *file_name) { snprintf(acf_name, sizeof acf_name, "%s", file_name); }
void mock_set_button(int i, int down) { if (i >= 0 && i < 3200) joy_buttons[i] = down; }

int mock_handler_count(void) {
  int n = 0;
  for (int i = 0; i < 64; i++) n += handlers[i].used;
  return n;
}

/* Run a command phase (0 begin, 1 continue, 2 end) through its handlers, as a
   key press would. Returns 1 if X-Plane would go on to handle it itself. */
int mock_press(const char *name, int phase) {
  void *c = NULL;
  for (int i = 0; i < ncmds; i++) if (strcmp(cmds[i].name, name) == 0) c = &cmds[i];
  if (!c) return -1;
  for (int i = 0; i < 64; i++)
    if (handlers[i].used && handlers[i].cmd == c && !handlers[i].cb(c, phase, handlers[i].refcon)) return 0;
  return 1;
}

static void lose_camera(void) {
  if (cam_cb) {
    CameraControl cb = cam_cb;
    cam_cb = NULL;
    cb(&cam_pos, 1, cam_ref);
  }
}

/* What X-Plane does when the view changes: set the view datarefs and take the
   camera back from a plugin that asked for it "until the view changes". */
void mock_set_view(int view_type, int external) {
  Ref *vt = ref_named("sim/graphics/view/view_type");
  int changed = vt && (int)vt->value != view_type;
  mock_define("sim/graphics/view/view_type", view_type);
  mock_define("sim/graphics/view/view_is_external", external);
  if (changed && cam_duration == 1) lose_camera();
}

/* One rendered frame: returns 1 and the camera if a plugin drew it. */
int mock_render(double *out) {
  if (!cam_cb) return 0;
  CameraPosition p = cam_pos;
  int keep = cam_cb(&p, 0, cam_ref);
  if (!keep) { cam_cb = NULL; return 0; }
  cam_pos = p;
  out[0] = p.x; out[1] = p.y; out[2] = p.z;
  out[3] = p.pitch; out[4] = p.heading; out[5] = p.roll; out[6] = p.zoom;
  return 1;
}

/* ---- XPLM API ---- */
void *XPLMFindDataRef(const char *name) {
  if (strcmp(name, "sim/joystick/joystick_button_values") == 0) return &joy_token;
  return ref_named(name);
}
int XPLMGetDatavi(void *r, int *values, int offset, int max) {
  if (r != &joy_token) return 0;
  if (!values) return 3200;
  int n = 0;
  for (int i = offset; i < 3200 && n < max; i++) values[n++] = joy_buttons[i];
  return n;
}
int XPLMCanWriteDataRef(void *r) { return r != NULL; }
int XPLMGetDatai(void *r) { return r ? (int)((Ref *)r)->value : 0; }
float XPLMGetDataf(void *r) { return r ? (float)((Ref *)r)->value : 0.0f; }
double XPLMGetDatad(void *r) { return r ? ((Ref *)r)->value : 0.0; }
void XPLMSetDataf(void *r, float v) { if (r) ((Ref *)r)->value = v; }

void *XPLMFindCommand(const char *name) {
  for (int i = 0; i < ncmds; i++) if (strcmp(cmds[i].name, name) == 0) return &cmds[i];
  return NULL;
}
void XPLMCommandOnce(void *c) {
  if (!c) return;
  const char *name = ((Cmd *)c)->name;
  snprintf(last_cmd, sizeof last_cmd, "%s", name);
  cmd_count++;
  if (strcmp(name, "sim/view/3d_cockpit_cmnd_look") == 0) mock_set_view(1026, 0);
  else if (strcmp(name, "sim/view/chase") == 0) mock_set_view(1017, 1);
}

void XPLMRegisterCommandHandler(void *cmd, CommandCallback cb, int before, void *refcon) {
  for (int i = 0; i < 64; i++)
    if (!handlers[i].used) {
      handlers[i] = (Handler){ cmd, cb, before, refcon, 1 };
      return;
    }
}
void XPLMUnregisterCommandHandler(void *cmd, CommandCallback cb, int before, void *refcon) {
  for (int i = 0; i < 64; i++)
    if (handlers[i].used && handlers[i].cmd == cmd && handlers[i].cb == cb && handlers[i].before == before && handlers[i].refcon == refcon) {
      handlers[i].used = 0;
      return;
    }
}

void XPLMGetNthAircraftModel(int index, char *file_name, char *path) {
  (void)index;
  snprintf(file_name, 256, "%s", acf_name);
  snprintf(path, 512, "/X-Plane 12/Aircraft/%s", acf_name);
}

void XPLMControlCamera(int how_long, CameraControl cb, void *refcon) {
  cam_cb = cb; cam_ref = refcon; cam_duration = how_long;
  cam_pos.zoom = 1;
}
void XPLMDontControlCamera(void) { cam_cb = NULL; }
int XPLMIsCameraBeingControlled(int *duration) {
  if (duration) *duration = cam_duration;
  return cam_cb != NULL;
}
void XPLMReadCameraPosition(CameraPosition *p) { *p = cam_pos; }

static int probe_token;
void *XPLMCreateProbe(int type) { (void)type; return &probe_token; }
void XPLMDestroyProbe(void *p) { (void)p; }
int XPLMProbeTerrainXYZ(void *p, float x, float y, float z, ProbeInfo *info) {
  (void)p; (void)x; (void)y; (void)z;
  probe_count++;
  if (info->structSize != (int)sizeof(ProbeInfo)) return 1;
  info->locationX = x; info->locationY = (float)ground_y; info->locationZ = z;
  info->normalX = 0; info->normalY = 1; info->normalZ = 0;
  info->is_wet = 0;
  return 0;
}

/* Flat earth, 111120 m per degree, with a local origin that can move. */
void XPLMLocalToWorld(double x, double y, double z, double *lat, double *lon, double *alt) {
  *lat = -(z + origin_z) / 111120.0;
  *lon = (x + origin_x) / 111120.0;
  *alt = y;
}
void XPLMWorldToLocal(double lat, double lon, double alt, double *x, double *y, double *z) {
  *x = lon * 111120.0 - origin_x;
  *z = -lat * 111120.0 - origin_z;
  *y = alt;
}
