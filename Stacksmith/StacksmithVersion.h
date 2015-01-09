#include "svn_version.h"

#define STACKSMITH_SHORT_VERSION	1.0
#define STACKSMITH_BETA_SUFFIX		a11 (SVN_VERSION_NUM)

#define STACKSMITH_VERSION			SSV_PASTE(STACKSMITH_SHORT_VERSION,STACKSMITH_BETA_SUFFIX)

#define SSV_PASTE1(a,b)				a ## b
#define SSV_PASTE(a,b)				SSV_PASTE1(a,b)
