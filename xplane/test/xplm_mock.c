// Minimal stand-in for X-Plane's XPLM library, for testing cinematic_view.lua
// outside X-Plane: datarefs, the camera API, terrain probes and the timer.
#include <string.h>
#include <stdlib.h>

typedef struct { char name[128]; int type; int i; float f; double d; float *vf; int *vi; int n; int readonly; } DR; // type 1 int, 2 float, 4 double, 8 float array, 16 int array
static DR drs[128];
static int ndrs = 0;
static float elapsed = 0;
typedef int (*cam_f)(void *, int, void *);
static cam_f cam_cb = 0;
static void *cam_refcon = 0;
static int cam_duration = 0;
static float ground_y = 0;
static float axes[500];
static int buttons[3200];

static DR *add(const char *name, int type) { DR *d = &drs[ndrs++]; memset(d, 0, sizeof *d); strncpy(d->name, name, 127); d->type = type; return d; }

static void init(void) {
    if (ndrs) return;
    const char *dbl[] = {"sim/flightmodel/position/local_x","sim/flightmodel/position/local_y","sim/flightmodel/position/local_z","sim/flightmodel/position/elevation",0};
    const char *flt[] = {"sim/flightmodel/position/psi","sim/flightmodel/position/theta","sim/flightmodel/position/phi",
        "sim/flightmodel/position/local_vx","sim/flightmodel/position/local_vy","sim/flightmodel/position/local_vz",
        "sim/flightmodel/position/y_agl","sim/operation/misc/frame_rate_period",
        "sim/graphics/view/pilots_head_x","sim/graphics/view/pilots_head_y","sim/graphics/view/pilots_head_z",
        "sim/graphics/view/pilots_head_psi","sim/graphics/view/pilots_head_the","sim/graphics/view/pilots_head_phi",
        "sim/aircraft/view/acf_peX","sim/aircraft/view/acf_peY","sim/aircraft/view/acf_peZ",
        "sim/aircraft/weight/acf_m_max","sim/flightmodel/forces/g_nrml",0};   // acf_size_x/z deliberately missing
    const char *ints[] = {"sim/time/paused","sim/graphics/view/view_type","sim/graphics/VR/enabled",
        "sim/flightmodel/failures/onground_any",0};
    for (int i = 0; dbl[i]; i++) add(dbl[i], 4);
    for (int i = 0; flt[i]; i++) add(flt[i], 2);
    for (int i = 0; ints[i]; i++) add(ints[i], 1);
    // made-up focus settings, to check the script finds and drives them by name
    add("mock/camera/focus_distance_m", 2);
    add("mock/camera/auto_focus", 1);
    add("mock/camera/dof_enabled", 1)->readonly = 1;
    DR *a = add("sim/joystick/joystick_axis_values", 8); a->vf = axes; a->n = 500;
    DR *b = add("sim/joystick/joystick_button_values", 16); b->vi = buttons; b->n = 3200;
}

void *XPLMFindDataRef(const char *name) { init(); for (int i = 0; i < ndrs; i++) if (!strcmp(drs[i].name, name)) return &drs[i]; return 0; }
int XPLMGetDatai(void *r) { return r ? ((DR *)r)->i : 0; }
void XPLMSetDatai(void *r, int v) { if (r) ((DR *)r)->i = v; }
float XPLMGetDataf(void *r) { return r ? ((DR *)r)->f : 0; }
void XPLMSetDataf(void *r, float v) { if (r) ((DR *)r)->f = v; }
double XPLMGetDatad(void *r) { return r ? ((DR *)r)->d : 0; }
void XPLMSetDatad(void *r, double v) { if (r) ((DR *)r)->d = v; }
// the dataref list (X-Plane 12)
typedef struct { int structSize; const char *name; int type; int writable; int owner; } drinfo_t;
int XPLMCountDataRefs(void) { init(); return ndrs; }
void XPLMGetDataRefsByIndex(int offset, int count, void **out) { for (int i = 0; i < count; i++) out[i] = (offset + i < ndrs) ? &drs[offset + i] : 0; }
void XPLMGetDataRefInfo(void *r, drinfo_t *info) { DR *d = r; if (!d || info->structSize != sizeof(drinfo_t)) return; info->name = d->name; info->type = d->type; info->writable = !d->readonly; info->owner = 0; }
int XPLMGetDatavf(void *r, float *out, int off, int max) { DR *d = r; if (!d || d->type != 8) return 0; if (!out) return d->n; int n = 0; for (int i = off; i < d->n && n < max; i++) out[n++] = d->vf[i]; return n; }
int XPLMGetDatavi(void *r, int *out, int off, int max) { DR *d = r; if (!d || d->type != 16) return 0; if (!out) return d->n; int n = 0; for (int i = off; i < d->n && n < max; i++) out[n++] = d->vi[i]; return n; }
float XPLMGetElapsedTime(void) { return elapsed; }
void XPLMControlCamera(int how, void *f, void *refcon) { cam_cb = (cam_f)f; cam_refcon = refcon; cam_duration = how; }
void XPLMDontControlCamera(void) { cam_cb = 0; cam_duration = 0; }
typedef struct { int structSize; float locationX, locationY, locationZ, normalX, normalY, normalZ, velocityX, velocityY, velocityZ; int is_wet; } probe_t;
static int probe_dummy;
void *XPLMCreateProbe(int t) { return &probe_dummy; }
void XPLMDestroyProbe(void *p) {}
int XPLMProbeTerrainXYZ(void *p, float x, float y, float z, probe_t *out) { if (out->structSize != sizeof(probe_t)) return 1; out->locationX = x; out->locationY = ground_y; out->locationZ = z; return 0; }

// test helpers
void mock_set_time(float t) { elapsed = t; }
int mock_camera_controlled(void) { return cam_cb != 0; }
int mock_camera_duration(void) { return cam_duration; }
typedef struct { float x, y, z, pitch, heading, roll, zoom; } cam_t;
int mock_call_camera(cam_t *pos, int losing) { if (!cam_cb) return -1; int r = cam_cb(pos, losing, cam_refcon); if (!r) { cam_cb = 0; } return r; }
void mock_set_ground(float g) { ground_y = g; }
void mock_set_axis(int i, float v) { axes[i] = v; }
void mock_set_button(int i, int v) { buttons[i] = v; }
