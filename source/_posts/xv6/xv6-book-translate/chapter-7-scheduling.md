---
title: Chapter 7 调度
date: 2022-11-05 14:30:00
categories:
- xv6
- xv6-book中文翻译
---
# Chapter 7 调度
任何操作系统都可能允许比 CPU 核更多的进程，所以需要在进程间分时复用 CPU 。理想情况下，CPU 共享对进程是透明的。一个常规的做法是将进程多路复用到硬件CPU上，为每个进程提供虚拟 CPU 的错觉。本章将会讲解 xv6 是如何实现这个多路复用的。

## 复用
xv6 有两种方式在每个 CPU 上进行进程切换实现多路复用。首先，xv6 的 `sleep` 和 `wakeup` 机制会在进程等待设备 IO 完成或者子进程退出的时候进行切换。其次，xv6 会周期性的强制切换，以应对一个进程计算过长时间的情况。多路复用创造了一种每个进程都有自己独立 CPU 的错觉，就像 xv6 使用内存分配器和页表为每个进程创造了一种有自己内存的错觉一样。

实现多路复用带来了一些挑战。第一，如何从一个进程切换到另一个进程。尽管上下文切换很简单，但实现确是 xv6 中的一些不透明的代码。第二，如果让强制切换对用户态透明？ xv6 使用标准的时钟中断驱动上下文切换。第三，多个CPU可能并发的进行进程切换，需要一个锁方案来避免竞争。第四，进程的内存和其它资源必须在进程退出时释放，但是它并不能释放所有的资源，因为在使用期间它不能释放自己的内核栈。第五，每个 CPU 核都必须知道现在在执行哪个进程这样系统调用时才能有正确大而内核状态。最后，`sleep` 和 `wakeup` 允许进程让出 CPU 并进入休眠状态以等待事件，并允许另一个进程唤醒第一个进程。 需要注意由于唤醒通知丢失而引起的竞争。 xv6 尽可能简单的去解决这些问题，但代码还是非常棘手的。
![22834193-917ce84c9f3312e3.png](https://s2.loli.net/2022/11/05/kdM6aQImu9Po3te.png)

## Code: 上下文切换
上图是一个用户进程切换到另一个进程的步骤：用户内核过度到旧进程的内核线程，切换到当前CPU的调度线程上，上下文切换到心进程的内核进程，陷阱返回到用户进程。xv6 有一个独立的线程用于保存寄存器和栈。因为在进程的内核栈上执行是不安全的。其他CPU会唤醒进程，造成两个CPU使用同一个内核栈的危险。本节，将会解释内核线程和调度线程之间的切换。

从一个线程切换到另一个线程，涉及保存旧线程的 CPU 寄存器，并恢复新线程以前保存的寄存器的值。保存和恢复程序计数器以及栈指针意味着 CPU 切换了任务，切换了要执行的代码。

`swtch` 函数完成了保存和恢复内核线程。`swtch` 并不知道线程，只知道保存和恢复寄存器，这称做上下文。当一个进程需要让出 CPU 的时候，进程的内核线程调用 `swtch` 保存上下文并返回调度程序上下文。上下文即 `struct context` ，本身包含在一个进程的 `struct proc` 中。 `swtch` 使用两个参数： `struct context *old` 和 `struct context *new`。在 `old` 中保存旧的寄存器，从 `new` 中加载新的值，然后返回。

看一下 `swtch`。`usertrap` 调用 `yield`。`yield` 调用 `sched`，这会调用 `swtch` 保存在 `p->context` 中保存当前上下文。并切换到 `cpu->scheduler` 中保存的线程上下文中。

`swtch` 只保存 `callee-saved` 寄存器（被调用者保存寄存器，非易失性寄存器），`caller-saved` 寄存器如果需要的话，将由 C 代码保存在栈上。`swtch` 知道 `struct context` 中每个字段的偏移量，它不保存程序计数器，而是保存 `ra` 寄存器，ra 寄存器保存着 `swtch` 被调用时的返回地址。现在 `swtch` 从新的上下文中恢复，寄存器的值是上一个 `swtch` 保存的。当 `swtch` 返回时，它返回 ra 寄存器指向的地方，这是线程调用 `swtch` 的地方。出此之外，返回到一个新的线程栈中。

`sched` 调用 `swtch` 切换到每个 CPU 的调度上下文  `cpu->scheduler`。上下文由 `swtch` 保存。当 `swtch` 返回时，没有返回到 `sched` 而是 `scheduler`，它的栈指向当前 CPU 的调度栈。

## Code: 调度
上一节讲了 `swtch` 的实现细节，现在看看 一个进程通过 scheduler 切换到另一个线程的过程。调度器（scheduler）以一个特殊的线程存在与没一个 CPU 上，并运行 `scheduler` 函数。这个函数负责选择接下来运行哪个进程。一个进程想让出 CPU，必须先持有它的锁`p->lock`，释放它持有的其他锁，更新它的状态然后调用 `sched`。`yield`，`sleep`，`exit` 都遵循这个约定。`Sched` 双倍检查这些条件。这些条件的含义是：当持有锁时，中断应该是关闭的。最后，`sched` 调用 `swtch` 在 `p->context` 中保存当前上下文并切换到调度器的上下文中。`swtch` 返回到 `scheduler`  栈上，就像调度器返回调度器的循环中，找到一个进程运行，切换到它，然后重复这个过程。

我们看到 xv6 在整个 `swtch` 调用中都持有 `p->lock`：`swtch` 作为调用者必须持有这个锁，并将锁的控制传递给切换到的代码。这种约定对锁来说是不寻常的。通常获取锁的线程来释放锁，这比较容易理解。而对于上下文切换，有必要打破这个约定，因为 `p->lock` 保护的是 `state` 和 `context` 字段，但在 `swtch` 期间，这个约定不成立。如果在 swtch 期间没有持有 `p->lock`会出现问题，比如一个例子是， yield 之后，一个不同的 CPU 会运行这个进程并设置状态为 RUNABLE，但在 `swtch` 之前会使用内核栈，导致两个 CPU 运行在相同的栈上，这是不对的。

内核线程也会在 `sched` 里让出 CPU 并总是切换到调度器同样的位置，这个位置是钱一个调用 `sched` 的线程。因此，如果打应 xv6 线程切换的行号，会看到`(kernel/proc.c:475),(kernel/proc.c:509),(kernel/proc.c:475),(ker-nel/proc.c:509), `等等。在两个线程之前进行切换的这种过程有时被称为 `coroutines`，在这个例子中， `sched` 和 `scheduler` 互相切换。

有一种情况是调度器调用 `swtch` 但最终没有在 `sched` 中终止。那就是当一个新的进程首此被调度时，它是从 `forkret` 开始的，forkret 推出并释放 `p->lock` 。否则，新线程可能会在 `usertrapret` 开始。

`Scheduler` 运行一个简单的循环，找到一个线程运行，知道它让出 ，重复这个过程。调度器遍历进程表查找可运行的进程，可运行的进程 `p->state == RUNNABLE`。一旦找到这个进程，设置 CPU 当前上下文 `c->proc`，将这个进程标记为 RUNNING，调用 `swtch` 运行这个进程。

考虑调度器代码结构的一种方法是他强制在每个进程中使用一组不变量，并在这些不变量不满足时依然持有 `p->lock`。当进程处于 RUNNING 时，时钟中断 `yield` 必须能安全的切换到其他线程。这意味着 CPU 寄存器必须持有进程寄存器的值，并且 `c->proc` 必须指向这个进程。另一个不变量是，当进程处于 RUNNABLE 时，空闲 CPU 的寄存器必须能调度。这意味着 `p->context` 必须持有进程的寄存器，没有 CPU 执行在进程的内核栈上，没有CPU 的 c->procs 只想这个进程。当 `p->lock` 被持有时，这个条件永远不为真。

维护以上的不变量是 xv6 为什么总是在一个线程获取 `p->lock` 并在另一个线程中释放，比如在 yield 中获取锁，并在 `scheduler` 中释放。一旦 yield 开始修改进程的状态，这个锁就必须一直持有直到它的不变量被恢复：将 c->proc 清除。同样，一旦 调度器 开始将 RUNNABLE 进程转换到 RUNNING，直到内核线程完全运行之前，都不可以释放。

`p->lock`  也保护其他东西，`exit` 和 `wait` 的相互作用，避免唤醒丢失，避免进程退出是另一个进程的读写竞争。一个值得思考的问题是 `p->lock` 是否可以细分，以便为了性能。

## Code: mycpu 和 myproc
xv6 经常需要一个只想当前进程的结构体的指针。在单处理器上，可以有一个全局变量指向 proc。但这在多核机器上不可用，因为每个核都在执行不同的进程。解决这个问题的办法是利用每个核都有自己独立寄存器，可以使用这些寄存器来查找每个核的信息。

xv6 对每个 CPU 维护了一个 `struct cpu`，记录了当前 CPU 上运行的进程，在 CPU 的调度线程中保存寄存器，以及管理中断所需要的自旋锁。`mycpu` 函数返回一个指向当前 CPU 的结构体指针。RISC-V 为每个 CPU 进行了编号，给了一个 `hartid`。xv6 确保在内核态时，每个 CPU 的 `hartid` 运行在 CPU 的 `tp` 寄存器中。这允许 `mycpu` 使用 `tp` 寄存器来索引正确的 cpu 数据。

确保 CPU 的 tp 寄存器保持 CPU 的 hartid 有点复杂。`mstart` 在 CPU m-mod 启动流程中很早就设置了 tp 的值。`usertrapret` 在 trampoline 页中保存 `tp` 寄存器的值，因为用户程序可能会修改 tp 寄存器的值。最后，uservec 在进入内核时恢复保存的 tp 寄存器的值。编译器保证不使用 tp 寄存器。如果 RISC-V 允许 xv6 读取直接读取 `hartid` 会很方便，但这仅在 m-mod 上允许，在 s-mod 不允许。


返回的 `cpuid` 和 `mycpu` 是脆弱的，如果时钟终中断造成线程让出并迁移到另一个 CPU，先前的返回值将不再正确。为了避免这个问题，xv6 需要关中断并在使用完成后开启。

`myproc` 函数返回当前 CPU 上运行的进程。`myproc` 关中断，调用 `mycpu`，获取当前 CPU 上的进程 `c->proc`，并开启中断。`myproc` 的返回值可以在中断开启时安全的使用，因为即使线程迁移到别的 CPU，上下文仍然不变， proc 指针仍然可以使用。

## 休眠和唤醒
调度和锁帮助进程隐藏另一个进程的存在，但目前位置，我们还没有进程交互的抽象。有许多机制被用于解决这个问题。xv6 使用了休眠和唤醒，允许一个进程休眠等待事件并且唤醒另一个线程准备好了事件的进程。休眠和唤醒经常被成为 `sequence coordination` 和 `conditional synchronizatio` 机制。

为了阐明这一点，让我们考虑一种由生产者和消费者调度的称为`信号量 （semaphore）`的同步机制。信号量有一个计数器用于支持两个操作。`V `操作使这个计数器加1。`P` 操作一直等待到计数器非 0 时，减一并返回。如果只有一个生产者和一个消费者，在不同的 CPU 上执行，并且编译器不过分优化，以下实现就是正确的。

```
  1 struct semaphore {
  2     struct spinlock lock;
  3     int count;
  4 }
  5                                                                                                       
  6 void
  7 V(struct semaphore *s)
  8 {
  9     acquire(&s->lock);
 10     s->count +=1;
 11     release(&s->lock);
 12 }
 13 
 14 void
 15 P(struct semaphore *s)
 16 {
 17     while(s->count == 0)
 18         ;
 19     acquire(&s->lock);
 20     s->count -= 1;
 21     release(&s->lock);
 22 }
```
上边的实现是昂贵的。如果生产动作很少，消费很多，消费者会花费很多时间在循环等待计数器归零。消费者的 CPU 能找到比等待 `s->count` 归零更有意义的工作。避免这种无效等待需要一个方法让消费者让出 CPU，并在 V 操作自增后加一。

如此的话，跟进一步。假设这样一堆调用 `sleep` 和 `wakeup` 工作如下。`Sleep (chan)` 休眠在任意一个 chan 值上，称为 `wait channel`。`Sleep` 让调用的线程进行休眠，并释放这个 CPU 用于其他工作。`Wakeup (chan)` 唤醒所有在这个 `chan` 上等待的进程，也就是让 `sleep` 调用结束。如果这个 chan 上没有进程，`wakeup` 不会做任何事情。我们可以用sleep 和 wakeup 历来修改信号量的实现。
```
  6 void
  7 V(struct semaphore *s)
  8 {
  9     acquire(&s->lock);
 10     s->count +=1;
 11     wakeup(s);                                                                                        
 12     release(&s->lock);
 13 }
 14 
 15 void
 16 P(struct semaphore *s)
 17 {   
 18     while(s->count == 0)
 19         sleep(s);
 20     acquire(&s->lock);
 21     s->count -= 1;
 22     release(&s->lock);
 23 }
```
现在 P 操作将放弃 CPU 而不是自旋，这非常好。然而事实证明，在没有 `lost wake-up` 的问题下，这个设计方法并不是最直接的。当 P 在 `s->count == 0` 和 `sleep` 之间时，V 操作唤醒等待在 s 上的进程。但是发现没有进程处于休眠状态，所以什么都没有发生，然后 P 操作进入休眠状态。这样，即使 V 操作已经发生了，P 仍然陷入休眠。除非很幸运或者生产者再次调用 V，消费者将无限循环下去。

这个问题的根本原因在于不变量 P 只会在 V 错误的时候修改了 s->count == 0 的值。一个错误的做法是将获取锁移到 P 最开始处，这样 P 操作检查 count 值并休眠就是一个原子性操作。 P 操作确实避免了在计数器和休眠之前执行 V 操作，但是很明显，V 操作将无法获取到锁而造成死锁。

我们需要修改 `sleep` 的接口来修复这个问题，调用者必须给 `sleep` 传递一个`contition lock` 以将调用进程标记为睡眠释放这个锁，并等待在休眠通道上。这个锁会强制并发的 V 操作等待到 P 完全陷入休眠中，所以，`wakeup` 将找到休眠的进程并唤醒它。一旦消费者被唤醒，在返回前重新加锁。新的 sleep/wakeup 模型类似这样
```
  6 void
  7 V(struct semaphore *s)
  8 {
  9     acquire(&s->lock);
 10     s->count +=1;
 11     wakeup(s);
 12     release(&s->lock);
 13 }
 14 
 15 void
 16 P(struct semaphore *s)
 17 {
 18     acquire(&s->lock);
 19     while(s->count == 0)
 20         sleep(s, &s->lock);                                                                           
 21     acquire(&s->lock);
 22     s->count -= 1;
 23     release(&s->lock);
 24 }
```
此时，p 持有的锁阻止了 V 操作在不正确的时候修改 c->count 的值。记住，无论如何，我们需要 `sleep` 自动释放 `s->lock` 并让消费者进程进入休眠。

## Code: 休眠和唤醒
看一下 `kernel/proc.c` 中 sleep 和 wakeup 的实现。基础的想法是将当前进程状态设置为 SLEEPING 并调用 sched 让出 CPU。`wakeup` 检查进程休眠状态和 channel，将符合要求的进程标记为 RUNNABLE。sleep 和 wakeup 的调用者可以使用任何合适的数字作为 channel。xv6 里经常使用一个内核数据结构的地址参数作为 channel。

当 sleep 获取到 `p->lock` 的时候，即将进入休眠的进程同时持有了 `p->lock` 和 `lk`。P 持有 lk 是必须的，这保证 V 操作不会开始进行唤醒。当 sleep 持有 p->lock 后，就可以安全的释放 lk，这样其他的进程可能开始调用 wakeup，但是 wakeup 会等待 p->lock，直到这个进程真正的进入休眠才能获取到 p->lock，因此会等到 sleep 完全进入休眠状态，避免错过唤醒。（译者注：完全进入休眠的标志，是 sched 切换到调度器上下文，即 scheduler 函数，然后由 scheduler 释放掉当前线程的锁。）


这有一个并发问题：如果 lk 是一个和 p->lock 是同一个锁的话，sleep 将会死锁。但是如果调用 sleep 的进程已经持有了 p->lock，就不需要再做任何事情来避免唤醒丢失。所以此时加上条件判断即可。

现在 sleep 持有了 p->lock 而没有其他的锁，记录休眠通道，让进程进入休眠，修改进程的状态为 SLEEPING，调用 sched。一会就明白为什么 p->lock 是在 SLEEPING 之后释放的（由调度器 scheduler）。

有些时候，进程会获取条件锁，在设置休眠者等待的地方设置条件，并调用 `wakeup`。在 wakeup 期间持有条件锁是很重要的。 wakeup 循环查看进程也表，获取每个进程的进程锁 `p->lock`，因为它需要维护进程的状态并确保 sleep 和 wakeup 不会互相丢失。当 wakeup 找到一个进程匹配的 channel 并且其状态是 SLEEPING 时，修改进程的状态为 RUNNABLE。当下一次调度器运行的时候，将会看到这个就绪进程可以运行。

为什么 sleep 和 wakeup 的加锁规则会保证不会丢失唤醒。休眠进程在被标记为 SLEPING 之后，在条件检查之前要么持有条件锁，要么持有 p-> lock 或者来年跟着都有。调用 wakeup 的进程在 wakeup 循环中同时持有这两个锁。因此，唤醒者要么在消费者线程检查条件之前将条件置为真，要么唤醒者在线程被标记为 SLEEPING 之后检查检查进程状态。然后 wakeup 会看到休眠的进程并唤醒它。

有时多个进程会在同一个管道上休眠，例如，多个进程从一个 pipe 中读取。一个 wakeup 会将他们全部唤醒。首先运行的会获取到锁，并从 pipe 中读取数据。其他的进程会发现，尽管被唤醒，但没有数据可读。在他们看来，这种唤醒是虚假的。他们将再次陷入休眠。出于此考虑，sleep 总是在条件检查的循环里。

如果两次 sleep/wakeup 不小心选择了同一个通道，不会有任何危害：他们会看到虚假的唤醒，但是上边的循环能解决这个问题。休眠和唤醒的魅力在于即轻便又是一个中间层，调用者不用知道进程发生了哪些特殊的交互。

## Code: 管道
xv6 中实现的 `管道` 是使用 `sleep` 和 `wakeup` 进行生产者和消费者同步的更复杂的例子。我们在第一章看见了管道的接口：数据从管道的一端写入后被拷贝到内核缓冲区，然后在管道的另一端被读出。未来的章节会解释文件描述符对管道的支持，现在让我们先看看 `pipewrite` 和 `piperead` 的实现。

每个管道可以表示为一个 `struct pipe` 结构体，这个结构体包含一个 `锁` 和一个 `数据缓冲区`。 `nread` 和 `nwrite` 记录读取和写入的字节总数。缓冲区是环形的：`buf[PIPESIZE-1]` 后的数据写入 `buf[0]`。计数器不进行重置。这种约定可以实现区分一个满的缓冲区（nwrite == nread+PIPESIZE）和一个空的缓冲区（nwrite == nread），但这也意味着缓冲区的索引需要使用 `buf[nread % PIPESIZE]` 而不是 `buf[nread]`,`nwrite` 也是这样的。

让我们假设在两个不同的 CPU 上同时发生了 `piperead` 和 `pipewrite`。pipewrite 一开始获取管道的锁，这用于保护计数器，缓冲区以及相关的变量。piperead 然后也尝试获取锁，但是无法获取就会一直自旋等待以获取锁。当 piperead 在等待的时候， pipewrite 遍历需要写入的字节，依次将每个字节添加到管道中，在循环中可能发生缓冲区满了。这种情况下，pipewrite 调用 wakeup 唤醒在读通道上休眠的进程然后在写通道上休眠等待读端从缓冲区中取走数据。pipewrite 进程在休眠时会释放管道的锁。

现在管道锁可以被获取，piperead 获取然后进入他的临界区。发现 `pi->nread != pi->nwrite`，所以它进入循环中，从管道中拷贝数据并根据读到的数据增加 nread 计数。现在就有一些数据可以写了，所以 piperead 调用 wakeup 唤醒在写通道上休眠的进程。

管道的代码实现为读写分离了单独的休眠通道；这可能会使系统在有同一个管道上有多个读写的情况下更加高效。管道代码在一个检查休眠条件的循环中休眠；如果有多个写或者读，除了第一个唤醒的进程，其他进程会看见条件仍然为 false 然后继续休眠。

## Code: 等待，退出和杀死
`sleep` 和 `wakeup` 可以被用于多种等待的情况中。一个有趣的例子是在第一章介绍的，子进程退出和父进程等待之间交互的例子。当子进程死亡后，父进程可能在 `wait` 上休眠，或者可能在进行其他的事情。在后一种情况下，调用 `wait` 的进程必须发现子进程已经死亡了。在xv6里子进程死亡直到被 `wait` 发现然后退出这段时间会将调用者设置为 `ZOMBIE` 状态，直到父进程的 `wait` 注意高修改子进程的状态为 `UNUSED`。拷贝子进程的退出状态返回给父进程。如果父进程在子进程之前退出了，父进程将子进程交给 `init` 进程，这总会调用 `wait`，因此每个紫禁城都会有一个父进程在它之后做一些清理工作。这里实现的主要挑战在于父进程等待和子进程退出之间的竞争和死锁问题。

`wait` 使用调用者进程的 `p->lock` 作为条件锁以避免唤醒丢失，它在一开始就加锁。然后扫描进程表，找到在 `ZOMBIE` 状态的子进程，释放子进程的资源和 proc 结构信息。拷贝子进程的退出状态到 wait 指定的地址。如果 wait 找到一个还未退出的进程，调用 sleep 等待他们退出，然后在此扫描。特别说明，进程的 p->lock 作为条件锁在 sleep 中被释放。注意 wait 总是持有两个锁，在获取子进程的锁之前先获取本身的锁，因此所有的 xv6 都要遵循这样的锁顺序以避免死锁。

`wait` 检索每个进程的 `np->parent` 来查找他的子进程。这里在 np->lock 范围之外使用 np->parent，这违反了共享变量必须被锁保护的约定。这是因为 np 可能是当前进程的祖先，在这种情况下获取 np->lock 会造成死锁。解释一下在这里直接使用 np->parent 也是安全的，一个进程的 parent 字段仅仅会被它父进程改变，所以当 np->parent == p 为真时，这个值除了当前进程外，不会被其他进程修改。

 exit 记录进程的推出状态，释放资源，将子进程交给 init 进程，当进程的父进程处于 wait 状态时，唤醒父进程，将进程标记为 ZOMBIE，然后永久的让出 CPU。最后的几步有些复杂。正在退出的进程必须持有父进程的锁才能将他的状态设置为 ZOMBIE 并且将父进程唤醒，因为父进程的锁是一个条件锁保证在等待是不会丢失唤醒。子进程也必须持有他自己的锁，不然父进程可能会看到子进程的状态是 ZOMBIE 然后将其释放掉，但此时子进程仍然在运行。获取锁的顺序是避免死锁的重要保证。因为 wait 先获取父进程锁然后获取子进程锁，所以 exit 也必须使用相同的顺序。

exit 调用一个特殊的唤醒函数 `wakeup1`，这仅仅唤醒正在 wait 上休眠的的父进程。子进程在设置为 ZOMBIE 之前唤醒父进程看起来不正确，但其实是安全的，因为尽管 wakeup1 可能会使父进程运行，但 wait 中的循环不能检索子进程，直到子进程的锁被 scheduler 释放。所以 wait 无法看到正在退出中的进程，直到 exit 将他的状态设置为 ZOMBIE。（译者注：exit 代码先设置子进程状态为 ZOMBIE 再释放父进程的锁，在释放父进程的锁之前，如果父进程刚刚被唤醒，也是不能被运行，如果父进程处于 wait 的 sleep 循环中，也无法在调度器部分获得锁，也无法运行，而这里说的安全情况是无法拿到子进程的锁，合适吗？）

虽然 exit 允许进程自行终结，但是 kill 允许一个进程终结另一个进程。对 kill 来说直接销毁一个进程是很复杂的，因为目标进程可能正在另一个 CPU 上执行，可能正在更新一些内核敏感数据结构。因此 kill 只做很少的事情，设置目标程序的 `p->killed` 并且如果目标程序在休眠，唤醒它。最终目标进程会进入或者离开内核，在 usertrap 里，如果 p->killed 被设置为真，则会调用 exit。如果目标进程运行在用户态，它会因为系统调用或者时钟中断或其他中断很快进入内核。

如果目标进程在休眠，kill 调用 wakeup 将目标进程从休眠中唤醒。这里有一个潜在的隐患是等待条件此时还没有被正确的设置。然而，xv6 在调用 sleep 的地方都有一个循环在休眠返回后重复检测条件变量。一些调用 sleep 的地方也会在循环中检测 p->killed 是否被设置，如果设置的话就会中止当前正在进行的活动。当然这只有在中止活动不造成其他影响的情况下才会这样做。例如，pipe read 和pipe write 代码在 kill 标志被置位时会返回。最终代码会返回到 trap 中，然后再次检测 kill 标志并退出。

一些 xv6 的休眠循环不检测 p->killed。因为这些代码正处于多步系统调用中，应该是原子的。virtio 驱动就是一个例子，它并不检测 p->killed 因为磁盘操作可能是一系列文件系统的有序写入。一个正在等待磁盘 IO 的被中终结的进程在它完成当前系统调用并在 usertrap 看到 kill 标志之前不会退出。

## Real world
xv6 调度器实现了一个简单的调度策略，依次运行没个进程。这种策略被称为 `round robin`。真实的操作系统实现更复杂的策略，例如允许进程拥有优先级。这样高优先级的进程比低优先级进程更可能被系统调度。这种策略很快就会变得很复杂，因为经常有一些冲突的情况。例如，一些操作想要保证公平和更高的吞吐两。除此之外，复杂的策略会导致一些意外的交互情况例如 `priority inversion 优先级倒置` 和 `convoys 排队`。当一个低优先级进程和高优先级进程共享一把锁的时候会发生优先级倒置被低优先级持有的锁会影响高优先级的进程。排队是许多高优先级的进程等待低优先级进程的锁。一旦排队形成的时候，会持续很长的时间。为了避免这些问题，在复杂调度系统里需要添加额外的机制。

休眠和唤醒是简单且高效的同步手段，但也有一些其他的问题。第一个问题是一开始提到的要避免`lost wakeups`。最原始的 Unix 内核休眠只关中断，这就够了因为 Unix 运行在单核 CPU 上。由于 xv6 运行在多处理器上，所以为 sleep 添加了明确的锁。FreeBSD 的 msleep 也采用了相同的办法。Plan9 的sleep 使用了一个回调函数，该函数在进入休眠前持有调度器的锁运行。这个函数在最后检查休眠条件避免唤醒丢失。Linux 内核的 sleep 使用明确的进程队列，称为等待队列代替等待通道。队列有自己内部的锁。

在 wakeup 里扫描整个进程列表然后匹配 `休眠通道 chan` 效率有些低。一个更好的处理是在休眠和唤醒中使用一个保存休眠进程的数据结构来代替 chan。例如 Linux 操作系统的等待队列。Plan9 的休眠和唤醒将这种结构称为 `rendezvous point 汇合点`。许多线程库将这种相同的结构称为条件变量。在这种上下文里，休眠和唤醒操作被称为等待和信号。所有这些机制都有相同的地方，休眠条件在休眠期间被某种原子性的锁保护。

wakeup 的实现唤醒所有等待在特殊通道上的进程。操作系统将会调度这些进程并且会它们会对休眠条件的检查展开竞争。有这种行为的进程优势被称为 `thundering herd`，这最好能避免。大多数条件变量有两个用于唤醒的原语：`signal 信号` 和 `broadcast 广播`，信号用于唤醒一个进程，而广播用于唤醒所有等待的进程。

信号量也经常被用于同步。该计数通常对应于管道缓冲区中可用的字节书或者进程拥有的僵尸进程的数量。使用明确的计数作为抽象的一部分可以避免唤醒丢失的问题。对已经发生的唤醒有明确的计数。计数也能避免虚假的唤醒和 `thundering herd` 问题。

终止进程和清理它们为 xv6 引入了很多复杂性。在大多数系统上它们甚至更复杂，因为目标进程可能在内核深处休眠，这里的深处意思是展开它的堆栈需要很小心的编程。许多操作系统使用显示的异常处理机制展开堆栈例如 `longjmp`。此外，还有其他可能的事情导致休眠进程被唤醒，即使它等待的事件还没有发生。例如当 Unix 进程休眠休眠时，另一个进程可能发送给它一个信号。这种情况下，进程会从一个被中断的系统调用中返回 -1 并将错误码设置为 EINTR。应用程序可以检查这些值并决定接下来做什么。xv6 不支持信号，所以这种复杂性不存在。

xv6 对 kill 的支持是不完全让人满意的。有可能需要循环检查 p->killed。一个可能的问题是，及时 sleep 检查了 p->killed，在 sleep 和 kill 之间会有竞争。后者可能在目标进程设置 p->killed 之后但在 sleep 之前设置 p->killed 然后尝试唤醒目标进程。如果这种情况发生，目标进程不会注意到 p->killed 知道条件变量发生。或者稍晚一些或者从不会发生。（译者注：这里没明白，kill 设置状态需要加锁，sleep 循环也需要加锁，不可能中途发生这种情况啊？）

真实的操作系统在一个空闲列表里使用常量时间查找空闲的进程而不是线性时间查找。xv6 使用线性查找只是为了更简单。