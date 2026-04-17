#include "Cache.h"

static uint32_t log2_int(uint32_t n) {
  uint32_t res = 0;
  while (n >>= 1)
    res++;
  return res;
}

Cache::Cache(uint32_t size, uint32_t assoc, uint32_t blocksize,
             ReplacementPolicy policy, uint32_t inclusion)
    : size(size), assoc(assoc), blocksize(blocksize), policy(policy),
      inclusion(inclusion), next_level(NULL), prev_level(NULL),
      global_counter(0) {

  if (size == 0 || assoc == 0) {
    num_sets = 0;
    return;
  }

  num_sets = size / (assoc * blocksize);
  index_bits = log2_int(num_sets);
  offset_bits = log2_int(blocksize);
  index_mask = num_sets - 1;

  sets.resize(num_sets, std::vector<Block>(assoc));
  for (uint32_t i = 0; i < num_sets; ++i) {
    for (uint32_t j = 0; j < assoc; ++j) {
      sets[i][j].valid = false;
      sets[i][j].dirty = false;
      sets[i][j].tag = 0;
      sets[i][j].lru_counter = 0;
      sets[i][j].fifo_counter = 0;
    }
  }
}

void Cache::FindTag(uint32_t addr, uint32_t &tag, uint32_t &index) {
  index = (addr >> offset_bits) & index_mask;
  tag = addr >> (offset_bits + index_bits);
}

int Cache::FindBlock(uint32_t index, uint32_t tag) {
  for (uint32_t i = 0; i < assoc; ++i) {
    if (sets[index][i].valid && sets[index][i].tag == tag) {
      return (int)i;
    }
  }
  return -1;
}

int Cache::FindEmptyWay(uint32_t index) {
  for (uint32_t i = 0; i < assoc; ++i) {
    if (!sets[index][i].valid) {
      return (int)i;
    }
  }
  return -1;
}

int Cache::SelectVictim(
    uint32_t index, uint32_t access_index,
    std::map<uint32_t, std::deque<uint32_t>> &future_accesses) {
  if (policy == LRU) {
    uint32_t min_lru = sets[index][0].lru_counter;
    int victim = 0;
    for (uint32_t i = 1; i < (uint32_t)assoc; ++i) {
      if (sets[index][i].lru_counter < min_lru) {
        min_lru = sets[index][i].lru_counter;
        victim = i;
      }
    }
    return victim;
  } else if (policy == FIFO) {
    uint32_t min_fifo = sets[index][0].fifo_counter;
    int victim = 0;
    for (uint32_t i = 1; i < (uint32_t)assoc; ++i) {
      if (sets[index][i].fifo_counter < min_fifo) {
        min_fifo = sets[index][i].fifo_counter;
        victim = i;
      }
    }
    return victim;
  } else if (policy == OPTIMAL) {
    int victim = -1;
    uint32_t max_future = 0;
    bool found_never_accessed = false;

    for (uint32_t i = 0; i < (uint32_t)assoc; ++i) {
      uint32_t block_addr = (sets[index][i].tag << (index_bits + offset_bits)) |
                            (index << offset_bits);
      uint32_t block_id = block_addr >> offset_bits;

      std::deque<uint32_t> &accesses = future_accesses[block_id];

      // Remove past accesses
      while (!accesses.empty() && accesses.front() <= access_index) {
        accesses.pop_front();
      }

      uint32_t next_access = 0xFFFFFFFF;
      if (!accesses.empty()) {
        next_access = accesses.front();
      }

      if (next_access == 0xFFFFFFFF) {
        if (!found_never_accessed) {
          victim = i;
          found_never_accessed = true;
        }
      } else if (!found_never_accessed) {
        if (next_access > max_future) {
          max_future = next_access;
          victim = i;
        }
      }
    }
    return victim;
  }
  return 0;
}

void Cache::UpdateReplacementState(uint32_t index, int way, bool is_new_block) {
  if (policy == LRU) {
    sets[index][way].lru_counter = ++global_counter;
  } else if (policy == FIFO) {
    if (is_new_block) {
      sets[index][way].fifo_counter = ++global_counter;
    }
  }
}

bool Cache::Access(uint32_t addr, char op, uint32_t access_index,
                   std::map<uint32_t, std::deque<uint32_t>> &future_accesses) {
  uint32_t tag, index;
  FindTag(addr, tag, index);

  if (op == 'r')
    stats.reads++;
  else
    stats.writes++;

  int way = FindBlock(index, tag);

  if (way != -1) { // Hit
    if (op == 'w')
      sets[index][way].dirty = true;
    UpdateReplacementState(index, way, false);
    return true;
  } else { // Miss
    if (op == 'r')
      stats.read_misses++;
    else
      stats.write_misses++;

    way = FindEmptyWay(index);
    if (way == -1) { // Eviction needed
      way = SelectVictim(index, access_index, future_accesses);
      if (sets[index][way].dirty) {
        stats.writebacks++;
        if (next_level) {
          uint32_t victim_addr =
              (sets[index][way].tag << (index_bits + offset_bits)) |
              (index << offset_bits);
          next_level->Access(victim_addr, 'w', access_index, future_accesses);
        }
      }

      // Inclusion check
      if (inclusion == 1 && prev_level) {
        uint32_t victim_addr =
            (sets[index][way].tag << (index_bits + offset_bits)) |
            (index << offset_bits);
        bool was_dirty = false;
        prev_level->Invalidate(victim_addr, was_dirty);
        if (was_dirty) {
          prev_level->stats.forced_writebacks++;
        }
      }
    }

    // Allocate new block
    sets[index][way].valid = true;
    sets[index][way].tag = tag;
    sets[index][way].dirty = (op == 'w');
    UpdateReplacementState(index, way, true);

    if (next_level) {
      next_level->Access(addr, 'r', access_index, future_accesses);
    }

    return false;
  }
}

void Cache::Invalidate(uint32_t addr, bool &was_dirty) {
  uint32_t tag, index;
  FindTag(addr, tag, index);
  int way = FindBlock(index, tag);
  if (way != -1) {
    was_dirty = sets[index][way].dirty;
    sets[index][way].valid = false;
    sets[index][way].dirty = false;
  } else {
    was_dirty = false;
  }
}
