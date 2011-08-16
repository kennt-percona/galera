/*
 * Copyright (C) 2009-2010 Codership Oy <info@codership.com>
 */

#include <cerrno>
#include <unistd.h>
#include <galerautils.hpp>

#include "gcache_bh.hpp"
#include "GCache.hpp"

namespace gcache
{
    void
    GCache::reset()
    {

        rb.reset();
        ps.reset();

        mallocs  = 0;
        reallocs = 0;

        seqno_locked = SEQNO_NONE;
        seqno_min    = SEQNO_NONE;
        seqno_max    = SEQNO_NONE;

        seqno2ptr.clear();

#ifndef NDEBUG
        buf_tracker.clear();
#endif
    }

    void
    GCache::constructor_common() {}

    GCache::GCache (gu::Config& cfg, const std::string& data_dir)
        :
        config    (cfg),
        params    (config, data_dir),
        mtx       (),
        cond      (),
        seqno2ptr (),
        mem       (params.mem_size, seqno2ptr),
        rb        (params.rb_name, params.rb_size, seqno2ptr),
        ps        (params.dir_name,
                   params.keep_pages_size,
                   params.page_size,
                   /* keep last page if PS is the only storage */
                   !((params.mem_size + params.rb_size) > 0)),
        mallocs   (0),
        reallocs  (0),
        seqno_locked(SEQNO_NONE),
        seqno_min   (SEQNO_NONE),
        seqno_max   (SEQNO_NONE)
#ifndef NDEBUG
        ,buf_tracker()
#endif
    {
        constructor_common ();
    }

    GCache::~GCache ()
    {
        gu::Lock lock(mtx);
    }

    /*! prints object properties */
    void print (std::ostream& os) {}
}

#include "gcache.h"

void* gcache_malloc  (gcache_t* gc, size_t size)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    return gcache->malloc (size);
}

void  gcache_free    (gcache_t* gc, void* ptr)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    gcache->free (ptr);
}

void* gcache_realloc (gcache_t* gc, void* ptr, size_t size)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    return gcache->realloc (ptr, size);
}

void  gcache_seqno_init   (gcache_t* gc, int64_t seqno)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    gcache->seqno_init (seqno);
}

void  gcache_seqno_assign(gcache_t* gc, const void* ptr, int64_t seqno)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    gcache->seqno_assign (ptr, seqno);
}

void  gcache_seqno_release(gcache_t* gc, const void* ptr)
{
    gcache::GCache* gcache = reinterpret_cast<gcache::GCache*>(gc);
    gcache->seqno_release ();
}
