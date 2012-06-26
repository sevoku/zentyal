#ifndef SQUID_CONFIG_H
#include "config.h"
#endif

#ifndef SQUID_OS_FREEBSD_H
#define SQUID_OS_FREEBSD_H

#ifdef _SQUID_FREEBSD_

/****************************************************************************
 *--------------------------------------------------------------------------*
 * DO *NOT* MAKE ANY CHANGES below here unless you know what you're doing...*
 *--------------------------------------------------------------------------*
 ****************************************************************************/


#if USE_ASYNC_IO && defined(LINUXTHREADS)
#define _SQUID_LINUX_THREADS_
#endif

/*
 * Don't allow inclusion of malloc.h
 */
#if defined(HAVE_MALLOC_H)
#undef HAVE_MALLOC_H
#endif

#define _etext etext

/*
 *   This OS has at least one version that defines these as private
 *   kernel macros commented as being 'non-standard'.
 *   We need to use them, much nicer than the OS-provided __u*_*[]
 */
//#define s6_addr8  __u6_addr.__u6_addr8
//#define s6_addr16 __u6_addr.__u6_addr16
#define s6_addr32 __u6_addr.__u6_addr32

#endif /* _SQUID_FREEBSD_ */
#endif /* SQUID_OS_FREEBSD_H */