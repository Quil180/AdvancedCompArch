#include "Cache.h"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <string>
#include <vector>

using namespace std;

struct TraceEntry {
  char op;
  uint32_t addr;
};

void PrintCacheContents(const string &name, const Cache &cache) {
  cout << "===== " << name << " contents =====" << endl;
  uint32_t num_sets = cache.GetNumSets();
  uint32_t assoc = cache.GetAssoc();
  const auto &sets = cache.GetSets();

  for (uint32_t i = 0; i < num_sets; ++i) {
    cout << "Set     " << dec << i << ":      ";
    for (uint32_t j = 0; j < assoc; ++j) {
      if (sets[i][j].valid) {
        cout << hex << sets[i][j].tag << (sets[i][j].dirty ? " D" : "") << "  ";
      }
    }
    cout << endl;
  }
}

int main(int argc, char *argv[]) {
  // Checking if the arguments amount is correct
  if (argc != 9) {
    // Amount of arguments were not correct
    cerr << "Usage: " << argv[0]
         << " <BLOCKSIZE> <L1_SIZE> <L1_ASSOC> <L2_SIZE> <L2_ASSOC> "
            "<REPLACEMENT_POLICY> <INCLUSION_PROPERTY> <trace_file>"
         << endl;
    return 1;
  }

  // Gathering the arguments
  uint32_t blocksize = stoi(argv[1]);
  uint32_t l1_size = stoi(argv[2]);
  uint32_t l1_assoc = stoi(argv[3]);
  uint32_t l2_size = stoi(argv[4]);
  uint32_t l2_assoc = stoi(argv[5]);
  uint32_t policy_int = stoi(argv[6]);
  uint32_t inclusion = stoi(argv[7]);
  string trace_file = argv[8];

  // Getting the replacement policy
  ReplacementPolicy policy = (ReplacementPolicy)policy_int;

  // Open trace file
  ifstream trace(trace_file);
  if (!trace.is_open()) {
    string alt_path = "MachineProblem1 5/traces/" + trace_file;
    trace.open(alt_path);
    // Checking if the trace was opened properly
    if (!trace.is_open()) {
      cerr << "Error: Could not open trace file " << trace_file << endl;
      return 1;
    }
  }

  // After this the trace was opened correctly

  // Getting all of the entries in the trace
  vector<TraceEntry> entries;
  char op;
  uint32_t addr;
  while (trace >> op >> hex >> addr) {
    entries.push_back({op, addr});
  }
  trace.close();

  // Putting the future access if its perfectly done
  map<uint32_t, deque<uint32_t>> future_accesses;
  if (policy == OPTIMAL) {
    for (uint32_t i = 0; i < entries.size(); ++i) {
      future_accesses[entries[i].addr / blocksize].push_back(i);
    }
  }

  // initializing the l1 and l2 cache simulation
  Cache l1(l1_size, l1_assoc, blocksize, policy, 0);
  Cache *l2 = NULL;
  if (l2_size > 0) {
    l2 = new Cache(l2_size, l2_assoc, blocksize, policy, inclusion);
    l1.SetNextLevel(l2);
    if (inclusion == 1) {
      l2->SetPrevLevel(&l1);
    }
  }

  // Extract filename from trace_file path
  string trace_filename = trace_file;
  size_t last_slash = trace_file.find_last_of("/\\");
  if (last_slash != string::npos) {
    trace_filename = trace_file.substr(last_slash + 1);
  }

  // Print configuration to the screen
  cout << "===== Simulator configuration =====" << endl;
  cout << "BLOCKSIZE:             " << dec << blocksize << endl;
  cout << "L1_SIZE:               " << l1_size << endl;
  cout << "L1_ASSOC:              " << l1_assoc << endl;
  cout << "L2_SIZE:               " << l2_size << endl;
  cout << "L2_ASSOC:              " << l2_assoc << endl;
  cout << "REPLACEMENT POLICY:    "
       << (policy == LRU ? "LRU" : (policy == FIFO ? "FIFO" : "optimal"))
       << endl;
  cout << "INCLUSION PROPERTY:    "
       << (inclusion == 0 ? "non-inclusive" : "inclusive") << endl;
  cout << "trace_file:            " << trace_filename << endl;

  // Run simulation proper
  for (uint32_t i = 0; i < entries.size(); ++i) {
    l1.Access(entries[i].addr, entries[i].op, i, future_accesses);
  }

  // Print contents
  PrintCacheContents("L1", l1);
  if (l2) {
    PrintCacheContents("L2", *l2);
  }

  // Print results of simulation
  CacheStats s1 = l1.GetStats();
  double l1_miss_rate = (double)(s1.read_misses + s1.write_misses) / (s1.reads + s1.writes);

  cout << "===== Simulation results (raw) =====" << endl;
  cout << "a. number of L1 reads:        " << dec << s1.reads << endl;
  cout << "b. number of L1 read misses:  " << s1.read_misses << endl;
  cout << "c. number of L1 writes:       " << s1.writes << endl;
  cout << "d. number of L1 write misses: " << s1.write_misses << endl;
  cout << "e. L1 miss rate:              " << fixed << setprecision(6)
       << l1_miss_rate << endl;
  cout << "f. number of L1 writebacks:   " << s1.writebacks << endl;

  uint32_t l2_reads = 0, l2_read_misses = 0, l2_writes = 0, l2_write_misses = 0,
           l2_writebacks = 0;
  double l2_miss_rate = 0;
  uint32_t total_memory_traffic = 0;

  // if the l2 exists, get the data
  if (l2) {
    CacheStats s2 = l2->GetStats();
    l2_reads = s2.reads;
    l2_read_misses = s2.read_misses;
    l2_writes = s2.writes;
    l2_write_misses = s2.write_misses;
    l2_writebacks = s2.writebacks;
    if (l2_reads > 0)
      l2_miss_rate = (double)l2_read_misses / l2_reads;
    total_memory_traffic =
        l2_read_misses + l2_write_misses + l2_writebacks + s1.forced_writebacks;
  } else {
    total_memory_traffic = s1.read_misses + s1.write_misses + s1.writebacks;
  }

  // Print the l2 data no matter what
  cout << "g. number of L2 reads:        " << dec << l2_reads << endl;
  cout << "h. number of L2 read misses:  " << l2_read_misses << endl;
  cout << "i. number of L2 writes:       " << l2_writes << endl;
  cout << "j. number of L2 write misses: " << l2_write_misses << endl;
  if (l2_reads > 0)
    cout << "k. L2 miss rate:              " << fixed << setprecision(6)
         << l2_miss_rate << endl;
  else
    cout << "k. L2 miss rate:              0" << endl;
  cout << "l. number of L2 writebacks:   " << l2_writebacks << endl;
  cout << "m. total memory traffic:      " << dec << total_memory_traffic
       << endl;

  // Cleaning up l2 cache pointers if it exists
  if (l2) {
    delete l2;
  }

  // Program is done correctly!!
  return 0;
}
