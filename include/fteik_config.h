/* Copyright Ben Baker distributed under MIT */
#ifndef FTEIK_CONFIG_H__
#define FTEIK_CONFIG_H__ 1

/* using intel */
#define FTEIK_USE_INTEL
#define FTEIK_USE_H5

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#ifndef MAX
#define MAX(x,y) (((x) > (y)) ? (x) : (y))
#endif
#ifndef MIN
#define MIN(x,y) (((x) < (y)) ? (x) : (y))
#endif
#ifndef MAX3
#define MAX3(x,y,z) (((x) > MAX(y,z)) ? (x) : MAX(y,z))
#endif
#ifndef MIN3
#define MIN3(x,y,z) (((x) < MIN(y,z)) ? (x) : MIN(y,z))
#endif


#endif /* FTEIK_CONFIG_H__ */
