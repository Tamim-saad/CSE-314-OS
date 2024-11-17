// sample input by command line
// ./2005095 5 5 2 3 6 3

#include <bits/stdc++.h>
using namespace std;
using namespace chrono;

const int GALLERY1_LIMIT = 5;
const int CORRIDOR_LIMIT = 3;

system_clock::time_point start_time = system_clock::now();

mutex print_mtx;
mutex gallery1_mtx;
condition_variable gallery1_cv;
mutex corridor_mtx;
condition_variable corridor_cv;

mutex steps_mtx[3];
condition_variable steps_cv[3];
queue<int> steps_queue[3];

mutex read_try_mtx;
mutex resource_mtx;
mutex rc_mtx;
mutex writer_mtx;
int read_count = 0;

int gallery1_count = 0;
int corridor_count = 0;

int get_timestamp() {
  auto now = system_clock::now();
  return duration_cast<seconds>(now - start_time).count() + 1;
}

void print(const string &message) {
  lock_guard<mutex> lock(print_mtx);
  cout << message << endl;
}

class Visitor {
public:
  int id;
  int w, x, y, z;
  double lambda;
  default_random_engine generator;
  poisson_distribution<int> poisson_dist;
  uniform_int_distribution<int> uniform_dist;

  Visitor(int id, int w, int x, int y, int z, double lambda)
      : id(id), w(w), x(x), y(y), z(z), lambda(lambda), poisson_dist(lambda),
        uniform_dist(1, 3) {
    generator.seed(id);
  }

  void reader() {
    {
      unique_lock<mutex> lock(read_try_mtx);
      {
        lock_guard<mutex> rc_lock(rc_mtx);
        read_count++;
        if (read_count == 1) {
          resource_mtx.lock();
        }
      }
    }

    print("Visitor " + to_string(id) +
          " (Standard) is sharing the photo booth at timestamp " +
          to_string(get_timestamp()));
    this_thread::sleep_for(seconds(z));

    {
      lock_guard<mutex> rc_lock(rc_mtx);
      read_count--;
      if (read_count == 0) {
        resource_mtx.unlock();
      }
    }
  }

  void writer() {
    writer_mtx.lock();
    read_try_mtx.lock();
    resource_mtx.lock();
    read_try_mtx.unlock();
    writer_mtx.unlock();

    print("Visitor " + to_string(id) +
          " (Premium) is inside the photo booth at timestamp " +
          to_string(get_timestamp()));
    this_thread::sleep_for(seconds(z));

    resource_mtx.unlock();
  }

  void start() {
    int arrival_delay = poisson_dist(generator);
    this_thread::sleep_for(seconds(arrival_delay));

    print("Visitor " + to_string(id) + " has arrived at A at timestamp " +
          to_string(get_timestamp()));
    this_thread::sleep_for(seconds(w));

    print("Visitor " + to_string(id) + " has arrived at B at timestamp " +
          to_string(get_timestamp()));

    for (int i = 0; i < 3; ++i) {
      unique_lock<mutex> step_lock(steps_mtx[i]);
      steps_queue[i].push(id);
      steps_cv[i].wait(step_lock,
                       [this, i] { return steps_queue[i].front() == id; });

      print("Visitor " + to_string(id) + " is at step " + to_string(i + 1) +
            " at timestamp " + to_string(get_timestamp()));
      this_thread::sleep_for(seconds(1));

      steps_queue[i].pop();
      steps_cv[i].notify_all();
    }

    unique_lock<mutex> gallery1_lock(gallery1_mtx);
    gallery1_cv.wait(gallery1_lock,
                     [] { return gallery1_count < GALLERY1_LIMIT; });
    gallery1_count++;
    print("Visitor " + to_string(id) + " has entered Gallery 1 at timestamp " +
          to_string(get_timestamp()));
    gallery1_lock.unlock();

    this_thread::sleep_for(seconds(x));

    gallery1_lock.lock();
    gallery1_count--;
    gallery1_cv.notify_one();
    gallery1_lock.unlock();
    print("Visitor " + to_string(id) + " is exiting Gallery 1 at timestamp " +
          to_string(get_timestamp()));

    unique_lock<mutex> corridor_lock(corridor_mtx);
    corridor_cv.wait(corridor_lock,
                     [] { return corridor_count < CORRIDOR_LIMIT; });
    corridor_count++;
    print("Visitor " + to_string(id) +
          " has entered the glass corridor DE at timestamp " +
          to_string(get_timestamp()));
    corridor_lock.unlock();

    int corridor_delay = uniform_dist(generator);
    this_thread::sleep_for(seconds(corridor_delay));

    corridor_lock.lock();
    corridor_count--;
    corridor_cv.notify_one();
    corridor_lock.unlock();
    print("Visitor " + to_string(id) +
          " has exited the glass corridor DE at timestamp " +
          to_string(get_timestamp()));

    print("Visitor " + to_string(id) + " has entered Gallery 2 at timestamp " +
          to_string(get_timestamp()));

    int gallery2_delay =
        y + uniform_dist(generator) - 1; // y plus up to 2 seconds
    this_thread::sleep_for(seconds(gallery2_delay));

    print("Visitor " + to_string(id) +
          " is about to enter the photo booth at timestamp " +
          to_string(get_timestamp()));

    if (id >= 1001 && id < 2000) {
      reader();
    } else {
      writer();
    }

    print("Visitor " + to_string(id) +
          " has exited the photo booth at timestamp " +
          to_string(get_timestamp()));

    print("Visitor " + to_string(id) +
          " has exited the museum at F at timestamp " +
          to_string(get_timestamp()));
  }
};

int main(int argc, char *argv[]) {
  if (argc != 7) {
    cout << "Usage: " << argv[0] << " N M w x y z" << endl;
    return 1;
  }

  int N = stoi(argv[1]);
  int M = stoi(argv[2]);
  int w = stoi(argv[3]);
  int x = stoi(argv[4]);
  int y = stoi(argv[5]);
  int z = stoi(argv[6]);

  double lambda = 1.0;
  vector<thread> visitors;

  for (int i = 0; i < N; ++i) {
    int id = 1001 + i;
    Visitor visitor(id, w, x, y, z, lambda);
    visitors.emplace_back(&Visitor::start, visitor);
  }

  for (int i = 0; i < M; ++i) {
    int id = 2001 + i;
    Visitor visitor(id, w, x, y, z, lambda);
    visitors.emplace_back(&Visitor::start, visitor);
  }

  for (auto &visitor_thread : visitors) {
    if (visitor_thread.joinable()) {
      visitor_thread.join();
    }
  }
  return 0;
}
