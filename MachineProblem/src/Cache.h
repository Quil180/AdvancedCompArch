#ifndef CACHE_H
#define CACHE_H

#include <deque>
#include <list>
#include <stdint.h>
#include <string>
#include <vector>

#include <map>

// Setting the replacement policy options
enum ReplacementPolicy { 
  LRU = 0,
  FIFO = 1,
  OPTIMAL = 2
};

// Block Struct
struct Block {
  bool valid;
  bool dirty;
  uint32_t tag;
  uint32_t lru_counter;  // For LRU
  uint32_t fifo_counter; // For FIFO
};

// Stats for cache
struct CacheStats {
  uint32_t reads;
  uint32_t read_misses;
  uint32_t writes;
  uint32_t write_misses;
  uint32_t writebacks;
  uint32_t forced_writebacks;

  // Default values constructor incase I forget to initialize anything
  CacheStats()
      : reads(0), read_misses(0), writes(0), write_misses(0), writebacks(0),
        forced_writebacks(0) {}
};

class Cache {
public:
  // Constructor
  Cache(uint32_t size, uint32_t assoc, uint32_t blocksize,
        ReplacementPolicy policy, uint32_t inclusion);

  // Access Function (returns hit or miss)
  bool Access(uint32_t addr, char op, uint32_t access_index,
              std::map<uint32_t, std::deque<uint32_t>> &future_accesses);
  // Invalidate Function
  void Invalidate(uint32_t addr, bool &was_dirty);

  // Basic get data functions
  uint32_t GetNumSets() const { return num_sets; }
  uint32_t GetAssoc() const { return assoc; }
  const std::vector<std::vector<Block>> &GetSets() const { return sets; }
  CacheStats GetStats() const { return stats; }

  // More basic functions
  void SetNextLevel(Cache *next) { next_level = next; }
  void SetPrevLevel(Cache *prev) { prev_level = prev; }
  void IncrementWritebacks() { stats.writebacks++; }

private:
  uint32_t size; // size of cache
  uint32_t assoc; // associativity
  uint32_t blocksize; // size of blocks
  ReplacementPolicy policy; // replacement policy
  uint32_t inclusion; // inclusion policy

  uint32_t num_sets; // number of sets
  uint32_t index_bits; // amount of index bits
  uint32_t offset_bits; // amount of offset bits
  uint32_t index_mask; // the index mask

  std::vector<std::vector<Block>> sets; // array of all sets
  CacheStats stats; // stats block to be readable for output
  Cache *next_level; // linked list moment
  Cache *prev_level; // linked list moment 2
  uint32_t global_counter; // counter for cache

  // Functions for cache finding, and replacement, and updating, etc etc
  void FindTag(uint32_t addr, uint32_t &tag, uint32_t &index);
  int FindBlock(uint32_t index, uint32_t tag);
  int FindEmptyWay(uint32_t index);
  int SelectVictim(uint32_t index, uint32_t access_index,
                   std::map<uint32_t, std::deque<uint32_t>> &future_accesses);
  void UpdateReplacementState(uint32_t index, int way, bool is_new_block);
};

#endif
