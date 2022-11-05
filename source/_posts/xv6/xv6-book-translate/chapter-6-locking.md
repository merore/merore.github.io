---
title: Chapter 6 锁
date: 2022-11-05 11:09:07
categories:
- xv6
- xv6-book中文翻译
---
# Chapter 6 锁
包括 xv6 在内的大多数内核，都在交错执行多个任务。交错执行的一种原因是多处理器硬件：多 CPU 独立执行，例如 xv6 的 RISC-V。这些 CPU 共享物理内存，xv6利用共享来维护CPU 读写的数据结构。这种共享造成一种情况是，一个 CPU 正在读数据而同时另一个CPU正在更新数据；或是多个 CPU 在同时更新相同的数据；如果不仔细设计的话这种并行访问会造成不正确的结果并破坏数据结构。即使在单一处理器上，内核可能在多个线程之间切换，造成这些执行也是交错的。最后，如果在一个错误的时间发生设备中断，中断处理程序可能会损害数据结构。并发指的就是由于多处理器并行，线程切换，或者中断，多指令流交错执行。

内核中充满了并发访问的数据。例如，两个 CPU 可能同时调用 `kalloc`，从而同时从空闲列表弹出表头。内核设计允许一些并发，因为这样能够通过并行提高性能并提高响应速度。然而，因为并发的问题，内核设计者需要话费大量的时间来证明他们的正确性。有很多方法可以得到正确的代码，有一些更容易推理。并发下的正确策略和抽象被称为并发控制技术。

xv6 根据情况使用了一些并发控制技术。本章将会聚焦于广泛使用的一种并发控制技术，`锁`。锁提供互斥，确保同一时间只有一个 CPU 持有锁。如果一个程序员为每个个共享的数据关联了一个锁，并在每次使用数据时持有该锁，则这个数据只会同时被一个CPU 所使用。在这个方案下，我们可以看到所保护了数据。虽然锁是如此容易理解的并发控制机制，但锁的缺点是降低了性能，因为并行的操作被实际上顺序执行了。

剩下的章节会介真实情况绍 xv6 为什么需要锁，xv6 如何实现和使用锁。
![22834193-aa127715b246d58a.png](https://s2.loli.net/2022/11/05/uFRcD1x9HjMZyBs.png)

## 条件竞争
有一个例子说明我们为什么需要锁，考虑两个进程在不同的 CPU 上调用 `wait`。`wait` 释放子进程的内存。因此，在每个 CPU 上，内核将会调用 `kfree` 释放子进程的页。内核分配器维护了一个 `kallloc（）` 从空闲列表弹出表头，`kfree（）` 将页压入空闲列表。如果为了性能最优，我们可能希望两个进程能并行的执行 `kfree` 而不需要等待，但这不是 xv6 `kfree` 的正确实现。

如上图所示，链表在内存中是被两个CPU共享的，他们通过 load 和 store 指令操作链表。（真实情况处理器中有缓存，但行为上就是多处理器共享单一内存）如果没有并发请求，你可能会为链表实现一个这样的 `push` 操作。
```c
  1 struct element {
  2     int data;
  3     struct element* next;
  4 }
  5 
  6 strcut element* list = 0;
  7 
  8 void
  9 push(int data)
 10 {
 11     struct element* l;
 12
 13     l = malloc(sizeof *l);
 14     l->data = data;
 15     l->next = list;
 16     list = l;
 17 }
```

![22834193-6c9c0eac7c1d000c.png](https://s2.loli.net/2022/11/05/LQs31AtDBiSHdER.png)

如果在隔离的环境中执行的话，这个实现是没问题的。然而，如果这段代码有多个在同时执行就不对了。如果两个 CPU 都在执行 push 操作，可能同时执行到第 15 行，然后在执行 16 行，这会导致错误的结果。当两个操作发生时，后一个操作会覆盖前一个导致前一个丢失。

丢失的第 16 行操作被称为`条件竞争（race condition）`。条件竞争指的是内存被并发访问并且至少有一个访问是写操作。竞争通常是一个bug，无论是操作丢失或者读了尚未完成更新的数据。竞争的结果取决与 CPU 具体执行的时间和内存中操作的顺序，这会使竞争造成的错误难以重现和纠错。例如，在调试时加入打印语句可能会改变程序执行的时间，从而让竞争消失。

通过采用锁来避免竞争。锁确保互斥，同时只有一个CPU能在执行 push 中的敏感操作。这会使上面的场景变得不可能。正确的加锁版本的代码只需要很少几行。
```c
  1 struct element {
  2     int data;
  3     struct element* next;
  4 }
  5 
  6 strcut element* list = 0;
  7 struct lock listlock;
  8 
  9 void
 10 push(int data)
 11 {
 12     struct element* l;
 13     l = malloc(sizeof *l);
 14     l->data = data;
 15     acquire(&listlock);
 16     l->next = list;
 17     list = l;
 18     release(&listlock);
 19 }
```

在 `acquire` 和 `release` 之间的指令经常被称为临界区。锁通常被称为保护列表。

当我们说锁保护数据的时候，我们实际的意思是保护一些作用于数据上的不变量（比如链表例子中的 l，l->next）。这些不变量是维护数据结构的属性。通常，操作的正确性取决于操作开始的时候，这些不变量是否是预期的。有些操作可能会暂时修改不变量，但必须在完成之前重建。例如，在这个链表的例子里，不变量是指向链表的第一个指针 l 和这个元素的 next。push 操作在 17 行违反了这个不变量。 将 l 指向了下一个元素。由于第二个CPU执行的代码依赖于这些不变量，就发生了条件竞争。正确使用锁，可以保证同一时间只有一个 CPU 能够操作临界区的数据。这样当数据结构的不变量不成立时，CPU 不会操作数据结构。

你可以认为锁串行了临界区，因此保存了不变量。你还可以将受锁保护的临界去视为原子性的。这样每个人看到的都是完整的修改，而不会是片段。

虽然正确的使用锁可以矫正代码，但锁限制了性能。例如，如果两个进程并发调用 `kfree`，锁将这两个调用串行，我们不会因为两个CPU而带来任何的好处。如果多个进程同时想要一个锁，就是冲突，或者出现锁争用。以链表为例，内核可能为每个 CPU 维护一个 空闲列表，如果一个 CPU 的空闲列表为空，必须从其他 CPU 偷来内存。其他的使用场景或许还需要更复杂的设计。

锁的位置对性能也至关重要。例如，我们可以把 `acquire` 向前移动：这可能会降低性能，因为我们把 malloc 也串行了。Using locks 一节提供了在何处插入 `acquire` 和 `release` 的指南。

## Code: locks
xv6 有两种锁，`spinlock` 和 `sleep-locks`。我们从 spinlocks 开始。xv6 用`struct spinlock` 表示 spinlock。其中一个重要的字段是 `locked`，当锁被持有时是一个非0值，否则是 0 值。逻辑上，xv6 应该以这种方式请求一个锁。
```c
 1 void
  2 acquire(struct spinlock* lk)
  3 {
  4     for(;;) {
  5         if(lk->locked == 0){
  6             lk -> locked = 1;
  7             break;
  8         }
  9     }
 10 }
```

不幸的是，这个实现并不能保证多核互斥。如果两个 CPU 都走到了第 5 行，看到 `lk->locked` 是0，来你跟着都会持有这个锁，这违反了互斥性。我们需要让第 5 行和第 6 行成为一个原子操作。

由于锁被广泛使用，多核处理器通常会提供一些指令来实现 25,26 行的原子性。RISC-V 中，这个指令是 `amoswap r, a`。`amoswp` 从地址 a 出值，将 r 寄存器的内容写到这个地址，并把这个值放到 r 寄存器。这样的话，就交换了寄存器和地址的内容。它以原子的方式执行这个操作，使用特殊的硬件防止其他CPU对该地址进行读写。

xv6 的 `acquire` 使用了 C 库中的 `__sync_lock_test_and_set`。它归结为 `amoswap` 指令。它返回 lk->locked 中的旧值。`acquire` 函数在一个循环中包装 swap，多次尝试（spinning）直到获取锁。每次迭代都会检查以前的旧值，如果以前的值是 0, 我们就可以获得这个锁，并且交换会把 `lk->locked` 设置为 1。如果以前的值是 1, 说明其他 CPU 持有这个锁，事实上我们将 1 交换到 lk-> locked 也不会改变它的值。

一旦锁被获取，`acquire` 会进行记录获取锁的CPU用于debug。lk->cpu 字段被锁保护必须由持有锁时进行变更。

`release` 是对 `acquire` 的相对操作：清除 `lk->cpu` 字段并释放锁。从概念上讲，release 只需要把 lk->locked 置为0。但是 C 标准允许将赋值操作实现为多条存储指令，因此对于并发来说，一条赋值语句可能并不是原子的。相反，release 使用 c 库 的 `__sync_lock_release` 执行原子操作。这个操作也属于 `amoswap` 指令的一部分。

## 使用锁
xv6 在多个地方使用锁来避免条件竞争。就像上边说的，`kalloc` 和 `kfree` 是一个好的例子。尝试练习 1,2 看看如果省略了锁会发生什么。你可能会发现很触发不正确的行为，表明通过代码很难可靠的测试锁和竞争带来的错误。xv6 不太可能存在竞争。

使用锁的一个难点在于决定使用多少锁，以及每个锁应该保护哪些数据和不变量。这里有几个基本原则。首先，如果一个变量被一个CPU写操作时，另一个CPU也能读写它，应该使用锁让这两个操作不重叠。其次，记住锁是保护不变量的，如果一个不变量出现在内存多个位置，通常它们都需要被一个锁保护来维护不变量。

上边说的都是所需要被使用的情况，没说锁不需要使用的地方，对效率来说不过多使用锁是很重要的，因为锁会降低并行度。如果并行不重要的话，可以安排只有一个线程并不需要担心锁。一个简单的内核可以做到这一点，通过在进入内核时获取一个锁并在退出内核时释放锁（尽管像 pipe read 或者 wait 这种系统调用会出问题）。许多单处理器操作系统通过这种方法运行在多处理器上，这种方法有时被称为`big kernel lock`。但是这种方法牺牲了并行性，同时只能有一个 CPU 工作在内核态。如果内核有很重的计算任务，使用更多的细粒度锁会更有效，这样内核就可以在多 CPU 上并行执行。

xv6 的 `kalloc` 就是一个粗粒度锁的例子。分配器有一个锁保护的列表。如果不同 CPU 上的进程同时想分配页，都必须通过自旋等待获取锁。自旋会降低性能，因为自旋本身是没用的操作。如果因为锁的争用而浪费了大量的时间，可以通过修改分配器的设计，提供多个空闲列表来提高性能。每个CPU都有自己的空闲列表，以真正的允许并行。（译者注：很多降低锁竞争的常规手段，称为 per-CPU，广泛用于内存分配）。

一个细粒度锁的例子是，xv6 中每个文件的有一个锁。这样不同的进程操作不同的文件可以同时进行而不必互相等待。文件锁可以做的更细粒度，比如在同一个文件的不同位置上锁。总的来说，锁的粒度主要是出于性能和复杂度两方面考虑。

后续的章节会提到锁处理并发的例子。

## 死锁和顺序锁
如果内核代码的路径上需要同时持有多个锁，那么这些锁保持一个相同的顺序是很重要的。否则就会有`死锁`的可能。让我们看看 xv6 中的两处需要 A，B 锁的代码，第一处的锁顺序是先A后B，第二处是先B后A。假设线程 T1，在第一处先获取了 A 锁，线程 T2 在第二处获取了 B 锁。接下来，T1 会尝试获取 B，T2 会尝试获取 A。这两个操作将无限阻塞下去因为他们都需要对方持有的锁，且不会释放自己持有的锁。为了避免死锁，所有的代码都应该以相同的顺序来获取锁。需要全局锁顺序意味着锁是函数也是函数约定的一部分：调用着必须按照锁的顺序以相同的顺序进行函数调用。

由于 `sleep` 工作，xv6 可能有许多长度为 2 的顺序锁。例如，`consoleintr` 是一个处理输入字符的中断。当新的行到达时，所有等待控制台输入的程序都应该被唤醒。为了达到这个目的，`consoleintr` 唤醒时会持有一个 `cons.lock`，这会获取等待线程的锁并唤醒它。因此，避免死锁的是在获取任何线程之前先获取 `cons.lock`。xv6 中的文件系统拥有最长的锁调用链。例如，同时创建文件需要持有目录的锁，一个文件的 inode 锁，一个磁盘块 buffer 的锁，一个磁盘驱动锁`vdisk_lock`和调用的进程的锁`p->lock`。为了避免死锁，文件系统代码必须按上边的顺序持有锁。

遵守全局避免死锁的原则可能会非常困难。有时锁的顺序和程序的逻辑顺序是冲突的，比如，模块 M1 调用 模块 M2，但锁的顺序是先锁 M2 再锁 M1。还有些情况是我们事先并不知道这些锁是什么，我们只有在获取到一个锁的时候才能知道下一个要获取的锁是什么。这种情况会出现在文件系统中查找路径文件，和`wait`，`exit` 等代码查找子进程。最终，死锁与否还是受锁粒度的约束，因为更多的锁就会有更多死锁的可能。避免死锁也是内核实现的一个主要因素。

## 锁和中断处理
有些 xv6 spinlocks 保护的数据被线程和中断处理程序同时持有。例如当内核县城在 `sys_sleep` 读取 `ticks` 时，`clockintr` 时钟中断可能增加 `ticks` 的值。`tickslock` 会将这两个操作串行。

锁和中断的联系会产生潜在的问题。假设 `sys_sleep` 获取了 `tickslock`，CPU 产生了一个时钟中断。`clockintr` 会尝试获取 `tickslock`，发现它被别人持有，就会等待释放。这种情况下，`tickslock` 将永远不会释放：只有 `sys_sleep` 能够释放它，但是 `sys_sleep` 直到 `clockintr` 返回都不会再继续运行。所以 CPU 就死锁了，任何需要锁的代码也都冻结。

为了避免这种情况，中断处理程序使用的 spinlock 不能在中断开启的情况下被持有。xv6 更保守一些，当 CPU 持有锁的时候，xv6 总是禁用这个 CPU 上的中断。中断可能发生在其它 CPU 上，所以中断需要的锁可以等待其他不在同一个CPU 上的线程释放。

当 CPU 不在持有锁时，xv6 重新启用中断；这里必须做一点标记以应对临界区嵌套的情况。`acquire` 调用 `push_off`，`release` 调用 `pop_off` 来跟踪锁的层级。当计数器到 0 的时候，`pop_off` 恢复最外层的中断状态。`intr_off` 和 `intr_on` 两个函数在 RISC-V 中用于禁用和开启中断。

在 `acquire` 中，在设置 `lk->locked` 之前关闭中断很重要。如果两个反过来，在持有锁和关闭中断之间会有时间间隙，如果不幸的话，时钟中断将让整个系统死锁。同样，在释放锁只有调用`pop_off`也同样重要。

## 指令和内存排序
认为程序的执行顺序和源码语句的出先方式是一样的这是很自然的。然而，许多编译器和CPU会为了性能而乱序执行。如果一个指令需要许多时钟周期来完成，CPU 可能会提前发出指令，以便和其他指令重叠从而避免CPU停顿。例如，CPU 可能注意到两条连续的互不干扰的指令 A 和 B。如果 B 的输入比 A 先准备好，CPU 可能会先开始执行 B，或者重叠执行 A B。编译器可能进行同样的重排序操作。

编译器和 CPU 在重排序时遵循以下的原则以确保不会修改正确的指令结果。然而，这些原则是允许并发的情况下改变执行结果的，并在多核处理器上很容易就造成错误的结果。CPU 的排序规则也被称谓 `memory model （内存模型）`。

例如 `push` 中的代码， 如果 CPU 将第四行的 store 操作移动到 `release` 之后，将会造成很严重的错误。如果这样的重排序发生，就会在获取锁之前出现一个窗口时间，发现 list 有变动，并且发现没有初始化的`list->next`。

为了告诉硬件和编译器不要进行这种优化，xv6 在 `acquire` 和 `release` 中使用 `__sync_synchronize()`。`__sync_synchronize()` 是一个`memory barrier（内存屏障）`。它告诉编译器和CPU不要跨屏障进行`load`和`store`。由于 xv6 使用锁访问共享数据，所以 xv6 在大多数情况下强制排序。

## 休眠锁
有时，xv6 需要长时间的持有一个锁，比如文件系统会在读写硬盘上的内容时持有锁，而这些操作往往要花费数十毫米。长时间持有一个 spinlock 会导致浪费，因为在 spin 期间 CPU 做不了任何事情。spinlock 的另一个缺陷是在持续期间内不能让出 CPU。我们想要做的就是如果一个因为一个锁在等待磁盘操作的花，一个进程可以使用 CPU。持有 spinlock 期间让出 CPU 是不合法的，因为如果其他进程获取这个锁会导致整个操作系统死锁。因此，我们需要一种锁，当执行 acquire 的时候让出 CPU。并在持有锁的时候允许让出 CPU。

xv6 提供了这样一种锁 `sleep-locks` 以在等待时让出 CPU。第七章将详细讲解使用的技术。从上层来讲，一个  `sleep-lock` 拥有一个让 `spinlock` 保护的字段 `locked`。`acquiresleep` 将调用 sleep 以让出 CPU，并释放 spinlock。结果就是当执行 `acquiresleep` 的时候，其他线程可以执行。

由于 `sleep-locks` 启用了中断，所以不能被用于中断处理中。因为`acquiresleep` 可能会让出 CPU，sleep-lock 不能在 spinlock 的临界区内使用。spin-locks 适用于短临界区，因为等待总会浪费 CPU。而 sleep-lock 在耗时较长的操作上表现很好。

## Real world
尽管对并发原语和并行进行了多年的研究，但使用锁编程仍然面临巨大的挑战。将锁隐藏在更高级别的结构上是很好的做法例如同步队列。如果你的程序使用了锁，最好使用一些工具来检测条件竞争，因为你很容易忽略掉给一些不变量加锁的情况。

许多操作系统支持 POSIX 献策灰姑娘模型（pthreads），这允许用户进程在不同CPU 上运行多个线程。Pthreads 支持用户级别的锁，内存屏障等等。Pthreads 需要操作系统的支持。例如，如果一个线程因为系统调用阻塞了，另一个相同的进程可以运行在这个CPU上。另外，如果一个 pthreads 修改了它的进程地址空间，内核必须让这个进程上的其他线程更新以对地址空间的变更做出反应。

不使用原子指令也可以实现锁，但是代价很昂贵，所以许多操作系统使用原子指令。

如果多个 CPU 同时竞争一个锁，那么锁的代价是很昂贵的。如果一个 CPU 在自己的缓存中持有一个锁，当另一个也需要持有这个锁时，更新缓存的原子指令必须将缓存进行在两个 CPU 之间进行复制，这样可能导致其他缓存失效。从其他 CPU 的缓存中获取缓存行的开销可能比从本地缓存中获取的开销高几个数量级。

为了避免锁昂贵的开销，一些操作系统使用无锁的数据结构和算法。例如，链表的查询不需要锁，并且使用原子指令对链表进行插入。比起锁，无锁程序会更复杂，比如，它必须考虑指令和内存重排。锁程序已经很困难了，所以 xv6 避免无锁带来更复杂的问题。


总结：
1. 锁本身的实现依赖硬件提供的原子性的操作
2. 锁保护一些不变量，这些不变量会在操作过程中发生变动并最终稳定，这些过程就叫做临界区
3. 避免死锁的一种方法是对于多个锁连续持有的情况下，需要固定顺序
4. spinlock 需要关中断，用于让 CPU 绝对安全的持有共享资源
4. 并发问题的原因之一是一份资源被多CPU共享造成的，对这些共享资源操作可以加锁，也可以设计成 per-cpu 的无锁模式
5. 注意锁和中断处理的互相作用而造成的死锁，要考虑持有锁后如果发生中断，是否会死锁，是否要关中断。
6. 由于锁操作本身涉及的是多个 CPU 对共享资源的竞争，所以需要通过内存屏障来保证顺序执行。让锁正确的被 CPU 持有。
7. CPU 乱序执行只会对并行结果有影响，当我们通过锁保护了临界区操作后，就不再需要内存屏障了，所以一般用户态编程不会使用内存屏障，而大多数基础库，尤其是涉及线程操作的会使用内存屏障。
