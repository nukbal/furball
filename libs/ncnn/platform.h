#ifndef NCNN_PLATFORM_H
#define NCNN_PLATFORM_H

#define NCNN_STDIO 1
#define NCNN_STRING 1
#define NCNN_SIMPLEOCV 0
#if defined(__APPLE__)
#define NCNN_SIMPLEOMP 0
#else
#define NCNN_SIMPLEOMP 1
#endif
#define NCNN_SIMPLESTL 0
#define NCNN_SIMPLEMATH 0
#define NCNN_THREADS 1
#define NCNN_BENCHMARK 0
#define NCNN_C_API 1
#define NCNN_PLATFORM_API 0
#define NCNN_WINXP 0
#define NCNN_PIXEL 1
#define NCNN_PIXEL_ROTATE 0
#define NCNN_PIXEL_AFFINE 0
#define NCNN_PIXEL_DRAWING 0
#define NCNN_VULKAN 0
#define NCNN_SIMPLEVK 0
#define NCNN_SYSTEM_GLSLANG 0
#define NCNN_RUNTIME_CPU 0
#define NCNN_GNU_INLINE_ASM 0
#define NCNN_AVX 0
#define NCNN_XOP 0
#define NCNN_FMA 0
#define NCNN_F16C 0
#define NCNN_AVX2 0
#define NCNN_AVXVNNI 0
#define NCNN_AVXVNNIINT8 0
#define NCNN_AVXVNNIINT16 0
#define NCNN_AVXNECONVERT 0
#define NCNN_AVX512 0
#define NCNN_AVX512VNNI 0
#define NCNN_AVX512BF16 0
#define NCNN_AVX512FP16 0
#define NCNN_VFPV4 0
#define NCNN_ARM82 0
#define NCNN_ARM82DOT 0
#define NCNN_ARM82FP16FML 0
#define NCNN_ARM84BF16 0
#define NCNN_ARM84I8MM 0
#define NCNN_ARM86SVE 0
#define NCNN_ARM86SVE2 0
#define NCNN_ARM86SVEBF16 0
#define NCNN_ARM86SVEI8MM 0
#define NCNN_ARM86SVEF32MM 0
#define NCNN_MSA 0
#define NCNN_LSX 0
#define NCNN_LASX 0
#define NCNN_MMI 0
#define NCNN_RVV 0
#define NCNN_ZFH 0
#define NCNN_ZVFH 0
#define NCNN_XTHEADVECTOR 0
#define NCNN_INT8 1
#define NCNN_BF16 1
#define NCNN_FORCE_INLINE 1
#define NCNN_VERSION_STRING "1.0.20260526"
#define NCNN_VERSION_NUMBER 20260526

#include "ncnn_export.h"

#ifdef __cplusplus
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#elif defined(__ANDROID__) || defined(__OHOS__) || defined(__linux__) || defined(__APPLE__)

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

#endif

#if NCNN_THREADS

#if defined(_WIN32)
#include <process.h>
#else
#include <pthread.h>
#endif

#endif // NCNN_THREADS

#if __ANDROID_API__ >= 26
#ifndef VK_USE_PLATFORM_ANDROID_KHR
#define VK_USE_PLATFORM_ANDROID_KHR
#endif
#endif // __ANDROID_API__ >= 26

#include <stddef.h>

namespace ncnn {

// -----------------------------------------------------------------------------
// Mutex / ConditionVariable / Thread / TLS
// -----------------------------------------------------------------------------

#if NCNN_THREADS
#if defined(_WIN32)
#if NCNN_WINXP
class NCNN_EXPORT Mutex {
public:
    Mutex() { InitializeCriticalSection(&cs); }
    ~Mutex() { DeleteCriticalSection(&cs); }
    void lock() { EnterCriticalSection(&cs); }
    void unlock() { LeaveCriticalSection(&cs); }
private:
    friend class ConditionVariable;
    CRITICAL_SECTION cs;
};
class NCNN_EXPORT ConditionVariable {
public:
    ConditionVariable() {
        signal_event = CreateEvent(0, FALSE, FALSE, 0);
        broadcast_event = CreateEvent(0, TRUE, FALSE, 0);
    }
    ~ConditionVariable() { CloseHandle(signal_event); CloseHandle(broadcast_event); }

    void wait(Mutex& mutex) {
        mutex.unlock();

        HANDLE events[2] = { signal_event, broadcast_event };
        WaitForMultipleObjects(2, events, FALSE, INFINITE);

        mutex.lock();
    }
    void broadcast() { SetEvent(broadcast_event); ResetEvent(broadcast_event); }
    void signal() { SetEvent(signal_event); }

private:
    HANDLE signal_event;
    HANDLE broadcast_event;
};

#else // NCNN_WINXP

class NCNN_EXPORT Mutex {
public:
    Mutex() { InitializeSRWLock(&lock_); }
    ~Mutex() {}
    void lock() { AcquireSRWLockExclusive(&lock_); }
    void unlock() { ReleaseSRWLockExclusive(&lock_); }
private:
    friend class ConditionVariable;
    SRWLOCK lock_;
};

class NCNN_EXPORT ConditionVariable {
public:
    ConditionVariable() { InitializeConditionVariable(&condition_); }
    ~ConditionVariable() {}
    void wait(Mutex& mutex) { SleepConditionVariableSRW(&condition_, &mutex.lock_, INFINITE, 0); }
    void broadcast() { WakeAllConditionVariable(&condition_); }
    void signal() { WakeConditionVariable(&condition_); }
private:
    CONDITION_VARIABLE condition_;
};

#endif // NCNN_WINXP
class NCNN_EXPORT Thread {
public:
    Thread(void* (*start)(void*), void* args = nullptr) : start_(start), args_(args) {
        handle_ = reinterpret_cast<HANDLE>(_beginthreadex(nullptr, 0, run, this, 0, nullptr));
    }
    ~Thread() {}
    void join() { WaitForSingleObject(handle_, INFINITE); CloseHandle(handle_); }
private:
    static unsigned __stdcall run(void* value) {
        Thread* thread = static_cast<Thread*>(value);
        thread->start_(thread->args_);
        return 0;
    }
    HANDLE handle_;
    void* (*start_)(void*);
    void* args_;
};

class NCNN_EXPORT ThreadLocalStorage {
public:
    ThreadLocalStorage() : key_(TlsAlloc()) {}
    ~ThreadLocalStorage() { TlsFree(key_); }
    void set(void* value) { TlsSetValue(key_, value); }
    void* get() { return TlsGetValue(key_); }
private:
    DWORD key_;
};
#else // _WIN32
class NCNN_EXPORT Mutex {
public:
    Mutex() { pthread_mutex_init(&mutex_, nullptr); }
    ~Mutex() { pthread_mutex_destroy(&mutex_); }
    void lock() { pthread_mutex_lock(&mutex_); }
    void unlock() { pthread_mutex_unlock(&mutex_); }
private:
    friend class ConditionVariable;
    pthread_mutex_t mutex_;
};

class NCNN_EXPORT ConditionVariable {
public:
    ConditionVariable() { pthread_cond_init(&condition_, nullptr); }
    ~ConditionVariable() { pthread_cond_destroy(&condition_); }
    void wait(Mutex& mutex) { pthread_cond_wait(&condition_, &mutex.mutex_); }
    void broadcast() { pthread_cond_broadcast(&condition_); }
    void signal() { pthread_cond_signal(&condition_); }
private:
    pthread_cond_t condition_;
};

class NCNN_EXPORT Thread {
public:
    Thread(void* (*start)(void*), void* args = nullptr) { pthread_create(&thread_, nullptr, start, args); }
    ~Thread() {}
    void join() { pthread_join(thread_, nullptr); }
private:
    pthread_t thread_;
};

class NCNN_EXPORT ThreadLocalStorage {
public:
    ThreadLocalStorage() { pthread_key_create(&key_, nullptr); }
    ~ThreadLocalStorage() { pthread_key_delete(key_); }
    void set(void* value) { pthread_setspecific(key_, value); }
    void* get() { return pthread_getspecific(key_); }
private:
    pthread_key_t key_;
};
#endif // _WIN32
#else // NCNN_THREADS
class NCNN_EXPORT Mutex {
public:
    Mutex() {}
    ~Mutex() {}
    void lock() {}
    void unlock() {}
};
class NCNN_EXPORT ConditionVariable {
public:
    ConditionVariable() {}
    ~ConditionVariable() {}
    void wait(Mutex&) {}
    void broadcast() {}
    void signal() {}
};
class NCNN_EXPORT Thread {
public:
    Thread(void* (*)(void*), void* = nullptr) {}
    ~Thread() {}
    void join() {}
};

class NCNN_EXPORT ThreadLocalStorage {
public:
    ThreadLocalStorage() : data_(nullptr) {}

    ~ThreadLocalStorage() {}
    void set(void* value) { data_ = value; }
    void* get() { return data_; }
private:
    void* data_;
};
#endif // NCNN_THREADS

// -----------------------------------------------------------------------------
// Mutex guard
// -----------------------------------------------------------------------------

class NCNN_EXPORT MutexLockGuard {
public:
    explicit MutexLockGuard(Mutex& mutex) : mutex_(mutex) { mutex_.lock(); }
    ~MutexLockGuard() { mutex_.unlock(); }
private:
    Mutex& mutex_;
};

// -----------------------------------------------------------------------------
// MappedFile
//
// Added/required by ncnn 20260526.
// Used by Net for mmap-backed model loading.
// -----------------------------------------------------------------------------

#if defined(_WIN32)
class NCNN_EXPORT MappedFile {
public:
    MappedFile() : ptr(nullptr), _size(0), file(INVALID_HANDLE_VALUE), mapping(nullptr) {}
    ~MappedFile() { close(); }
    int open(const char* path) {
        close();
        file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

        if (file == INVALID_HANDLE_VALUE)
            return -1;

        LARGE_INTEGER liSize;
        if (!GetFileSizeEx(file, &liSize)) {
            close();
            return -1;
        }

        _size = static_cast<size_t>(liSize.QuadPart);
        if (_size == 0) {
            close();
            return -1;
        }

        mapping = CreateFileMapping(file, NULL, PAGE_READONLY, 0, 0, NULL);
        if (!mapping) {
            close();
            return -1;
        }

        ptr = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
        if (!ptr) {
            close();
            return -1;
        }
        return 0;
    }

    int open(const wchar_t* path) {
        close();
        file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

        if (file == INVALID_HANDLE_VALUE)
            return -1;

        LARGE_INTEGER liSize;
        if (!GetFileSizeEx(file, &liSize)) {
            close();
            return -1;
        }

        _size = static_cast<size_t>(liSize.QuadPart);
        if (_size == 0) {
            close();
            return -1;
        }

        mapping = CreateFileMapping(file, NULL, PAGE_READONLY, 0, 0, NULL);
        if (!mapping) {
            close();
            return -1;
        }

        ptr = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
        if (!ptr) {
            close();
            return -1;
        }

        return 0;
    }

    void close() {
        if (ptr) {
            UnmapViewOfFile(ptr);
            ptr = nullptr;
        }

        if (mapping) {
            CloseHandle(mapping);
            mapping = nullptr;
        }

        if (file != INVALID_HANDLE_VALUE) {
            CloseHandle(file);
            file = INVALID_HANDLE_VALUE;
        }
        _size = 0;
    }
    const void* mapped_ptr() const { return ptr; }
    size_t size() const { return _size; }

private:
    void* ptr;
    size_t _size;

    HANDLE file;
    HANDLE mapping;
};

#elif defined(__ANDROID__) || defined(__OHOS__) || defined(__linux__) || defined(__APPLE__)

class NCNN_EXPORT MappedFile {
public:
    MappedFile() : ptr(nullptr), _size(0), fd(-1) {}
    ~MappedFile() { close(); }
    int open(const char* path) {
        close();

        fd = ::open(path, O_RDONLY);

        if (fd < 0)
            return -1;

        struct stat st;

        if (fstat(fd, &st) < 0) {
            close();
            return -1;
        }

        _size = static_cast<size_t>(st.st_size);

        if (_size == 0) {
            close();
            return -1;
        }

        ptr = mmap(NULL, _size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (ptr == MAP_FAILED) {
            close();
            return -1;
        }

        return 0;
    }

    void close()
    {
        if (ptr && ptr != MAP_FAILED)
        {
            munmap(ptr, _size);
        }

        ptr = nullptr;

        if (fd >= 0)
        {
            ::close(fd);
            fd = -1;
        }

        _size = 0;
    }

    const void* mapped_ptr() const
    {
        return ptr;
    }

    size_t size() const
    {
        return _size;
    }

private:
    void* ptr;
    size_t _size;
    int fd;
};
#else
class NCNN_EXPORT MappedFile {
public:
    MappedFile() {}
    ~MappedFile() {}
    int open(const char*) { return -1; }
    void close() {}
    const void* mapped_ptr() const { return nullptr; }
    size_t size() const { return 0; }
};
#endif

// -----------------------------------------------------------------------------
// endian helpers
// -----------------------------------------------------------------------------

static inline void swap_endianness_16(void* value) {
    unsigned char* bytes = static_cast<unsigned char*>(value);
    unsigned char first = bytes[0];
    bytes[0] = bytes[1];
    bytes[1] = first;
}

static inline void swap_endianness_32(void* value) {
    unsigned char* bytes = static_cast<unsigned char*>(value);
    unsigned char first = bytes[0];
    unsigned char second = bytes[1];
    bytes[0] = bytes[3];
    bytes[1] = bytes[2];
    bytes[2] = second;
    bytes[3] = first;
}

} // namespace ncnn

// -----------------------------------------------------------------------------
// STL
// -----------------------------------------------------------------------------

#if NCNN_SIMPLESTL
#include "simplestl.h"
#else

#include <algorithm>
#include <list>
#include <vector>
#include <stack>
#include <string>

#endif

// -----------------------------------------------------------------------------
// math
// -----------------------------------------------------------------------------

#if NCNN_SIMPLEMATH
#include "simplemath.h"
#else
#include <math.h>
#include <fenv.h>
#endif

// -----------------------------------------------------------------------------
// Vulkan
// -----------------------------------------------------------------------------

#if NCNN_VULKAN
#if NCNN_SIMPLEVK
#include "simplevk.h"
#else
#include <vulkan/vulkan.h>
#endif
#include "vulkan_header_fix.h"
#endif // NCNN_VULKAN
#endif // __cplusplus

// -----------------------------------------------------------------------------
// logging
// -----------------------------------------------------------------------------

#if NCNN_STDIO
#if NCNN_PLATFORM_API && __ANDROID_API__ >= 8
#include <android/log.h>
#define NCNN_LOGE(...)                          \
    do                                          \
    {                                           \
        fprintf(stderr, ##__VA_ARGS__);         \
        fprintf(stderr, "\n");                  \
        __android_log_print(                     \
            ANDROID_LOG_WARN,                   \
            "ncnn",                             \
            ##__VA_ARGS__                       \
        );                                      \
    } while (0)
#else
#include <stdio.h>
#define NCNN_LOGE(...)                  \
    do                                  \
    {                                   \
        fprintf(stderr, ##__VA_ARGS__); \
        fprintf(stderr, "\n");          \
    } while (0)
#endif
#else
#define NCNN_LOGE(...)
#endif

// -----------------------------------------------------------------------------
// force inline
// -----------------------------------------------------------------------------

#if NCNN_FORCE_INLINE
#if defined(_MSC_VER)
#define NCNN_FORCEINLINE __forceinline
#elif defined(__GNUC__)
#define NCNN_FORCEINLINE inline __attribute__((__always_inline__))
#elif defined(__CLANG__)
#if __has_attribute(__always_inline__)
#define NCNN_FORCEINLINE inline __attribute__((__always_inline__))
#else
#define NCNN_FORCEINLINE inline
#endif
#else
#define NCNN_FORCEINLINE inline
#endif
#else
#define NCNN_FORCEINLINE inline
#endif
#endif // NCNN_PLATFORM_H
