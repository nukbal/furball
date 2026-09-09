#ifndef NCNN_PLATFORM_H
#define NCNN_PLATFORM_H

#define NCNN_STDIO 1
#define NCNN_STRING 1
#define NCNN_SIMPLEOCV 0
#define NCNN_SIMPLEOMP 1
#define NCNN_SIMPLESTL 0
#define NCNN_SIMPLEMATH 0
#define NCNN_THREADS 1
#define NCNN_BENCHMARK 0
#define NCNN_C_API 1
#define NCNN_PLATFORM_API 0
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
#define NCNN_MMI 0
#define NCNN_RVV 0
#define NCNN_ZFH 0
#define NCNN_ZVFH 0
#define NCNN_XTHEADVECTOR 0
#define NCNN_INT8 1
#define NCNN_BF16 1
#define NCNN_FORCE_INLINE 1
#define NCNN_VERSION_STRING "20250503"

#include "ncnn_export.h"

#ifdef __cplusplus

#if NCNN_THREADS
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <process.h>
#else
#include <pthread.h>
#endif

namespace ncnn {

#if defined(_WIN32)
class NCNN_EXPORT Mutex {
public:
    Mutex() { InitializeSRWLock(&lock_); }
    void lock() { AcquireSRWLockExclusive(&lock_); }
    void unlock() { ReleaseSRWLockExclusive(&lock_); }
private:
    friend class ConditionVariable;
    SRWLOCK lock_;
};

class NCNN_EXPORT ConditionVariable {
public:
    ConditionVariable() { InitializeConditionVariable(&condition_); }
    void wait(Mutex& mutex) { SleepConditionVariableSRW(&condition_, &mutex.lock_, INFINITE, 0); }
    void broadcast() { WakeAllConditionVariable(&condition_); }
    void signal() { WakeConditionVariable(&condition_); }
private:
    CONDITION_VARIABLE condition_;
};

class NCNN_EXPORT Thread {
public:
    Thread(void* (*start)(void*), void* args = nullptr) : start_(start), args_(args) {
        handle_ = reinterpret_cast<HANDLE>(_beginthreadex(nullptr, 0, run, this, 0, nullptr));
    }
    void join() { WaitForSingleObject(handle_, INFINITE); CloseHandle(handle_); }
private:
    static unsigned __stdcall run(void* value) {
        auto* thread = static_cast<Thread*>(value);
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
#else
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
#endif
#else
namespace ncnn {
class NCNN_EXPORT Mutex {
public:
    void lock() {}
    void unlock() {}
};
class NCNN_EXPORT ConditionVariable {
public:
    void wait(Mutex&) {}
    void broadcast() {}
    void signal() {}
};
class NCNN_EXPORT Thread {
public:
    Thread(void* (*)(void*), void* = nullptr) {}
    void join() {}
};
class NCNN_EXPORT ThreadLocalStorage {
public:
    void set(void*) {}
    void* get() { return nullptr; }
};
#endif

class NCNN_EXPORT MutexLockGuard {
public:
    explicit MutexLockGuard(Mutex& mutex) : mutex_(mutex) { mutex_.lock(); }
    ~MutexLockGuard() { mutex_.unlock(); }
private:
    Mutex& mutex_;
};

static inline void swap_endianness_16(void* value) {
    auto* bytes = static_cast<unsigned char*>(value);
    unsigned char first = bytes[0];
    bytes[0] = bytes[1];
    bytes[1] = first;
}

static inline void swap_endianness_32(void* value) {
    auto* bytes = static_cast<unsigned char*>(value);
    unsigned char first = bytes[0];
    unsigned char second = bytes[1];
    bytes[0] = bytes[3];
    bytes[1] = bytes[2];
    bytes[2] = second;
    bytes[3] = first;
}

}

#include <algorithm>
#include <fenv.h>
#include <list>
#include <math.h>
#include <stack>
#include <string>
#include <vector>

#endif

#if NCNN_STDIO
#include <stdio.h>
#define NCNN_LOGE(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
#else
#define NCNN_LOGE(...)
#endif

#if NCNN_FORCE_INLINE
#if defined(_MSC_VER)
#define NCNN_FORCEINLINE __forceinline
#elif defined(__GNUC__)
#define NCNN_FORCEINLINE inline __attribute__((__always_inline__))
#else
#define NCNN_FORCEINLINE inline
#endif
#else
#define NCNN_FORCEINLINE inline
#endif

#endif
