#ifndef JCONFIGINT_H
#define JCONFIGINT_H

#define BUILD "0"
#define INLINE inline __attribute__((always_inline))
#define THREAD_LOCAL _Thread_local
#define PACKAGE_NAME "mozjpeg"
#define VERSION "4.1.1"
#define SIZEOF_SIZE_T __SIZEOF_SIZE_T__

#if defined(__has_builtin)
#if __has_builtin(__builtin_ctzl)
#define HAVE_BUILTIN_CTZL 1
#endif
#endif

#if defined(__has_attribute)
#if __has_attribute(fallthrough)
#define FALLTHROUGH __attribute__((fallthrough));
#else
#define FALLTHROUGH
#endif
#else
#define FALLTHROUGH
#endif

#endif
