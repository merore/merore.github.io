---
title: Chapter 3 页表
date: 2022-11-03 09:43:18
categories:
- xv6
- xv6-book中文翻译
---
# Chapter 3 页表
页表是操作系统给每个进程提供私有地址空间和内存的一种机制。页表决定内存地址的意义以及哪些物理内存能够访问。他们允许 xv6 在同一块物理内存上隔离不同进程的地址空间。页表还间接的为 xv6 提供了一些手段：在多个地址空间中映射相同的内存地址，通过未分配的页来保护内核和用户栈。本章其余章节介绍 RICS-V 硬件提供的页表机制以及 xv6 将如何使用他们。

## 页表硬件
提醒一下，RISC-V 指令集（包括用户和内核）操作的都是虚拟地址。机器RAM，或者说是物理内存，是由物理地址进行索引。RISC-V 页表硬件通过映射虚拟地址到物理地址来连接这两种类型的地址。

xv6 运行在 Sv39 RISC-V上，这意味着 64 位虚拟地址中只有低 39 位地址被使用。高 25 位没有被使用。在 Sv39 中，一个 RISC-V` 页表页（page-table page）`是一个 2^27  `页表块（PTE）` 的数组。每个 PTE 包含一个 44 位的物理地址和10位标志。物理页表使用 39 位中的高 27 位在页表中找到 PTE，并且标志一个 56 位物理地址，物理地址的高 44 位来自 PTE 中的地址，低 12 位则直接从虚拟地址拷贝作为页内偏移。如图展示了单一页表示意图（每一个页表本身占用512 * 8个连续字节的物理内存，刚好也是一个物理页的大小 4096 字节）。页表让操作系统以 4096 字节大小为单位控制物理内存。这个单位被称作 `page （页）`。
![22834193-dad9da811179de3e.png](https://s2.loli.net/2022/11/03/EaSIsdWqmJVfQGF.png)

在 Sv39 RISC-V 中，高 25 位虚拟地址没有用于翻译，未来 RISC-V 可能会使用这些位来定义更多等级的翻译。物理地址也有增长空间，因为PTE 中还剩下 10 个比特位可用于扩展。

 如图 3.2 所示，实际的页表翻译有三个步骤。一个完整的页表是作为一个三级树存储在物理内存中的。树的根是一个 4096 字节的页表页，包含 512 个 PTEs（每个 PTE 占 8 字节，也就是 64 位，但仅使用低 55 位），这些 PTES 由两个部分组成，高 44 位保存的内容指向下一级页表页的物理地址，低 10 位是页表的一些标识位。对每一个虚拟地址来说，首先根据虚拟地址 27 位中的 高 9 位，来确定一个 0～512 之间的值，这个值表示一级页表中 PTE 的位置。然后便能根据这个 PTE，确定下一个页表页的位置。同理，中间的 9 位标识 第二级页表PTE。最终我们可以得到第三级 PTE。
![22834193-d2d202f6da9bd8d7.png](https://s2.loli.net/2022/11/03/wZK2nHPfl9ForpI.png)

当在进行三级页表查找转换时，如果任意一个地址对应的页表不存在导致地址无法翻译，硬件将会产生一个 `page-fault exception（页错误例外）`，并将这个例外交给内核处理。这种三级结构允许页表在虚拟地址大部分都未进行映射的情况下，直接省略整张页表，以节省页表页本身的内存开销。

每个 PTE 包含 flag 标志位以告诉硬件被关联的虚拟地址是否允许被使用。PTE_V 表示当前 PTE 是否存在（有效）；如果没有设置该标志位，任何指向该页的引用会造成例外。PTE_R 控制是否允许指令读取该页内容。PTE_W 控制是否允许指令写该页。PTE_X 控制是否是否允许 CPU 解释页的内容并执行。PTE_U 控制是否允许 user mode 访问该页；如果 PTE_U 没有设置，PTE 只能被 supervisor mode 使用。图 3.2 展示了这是如何工作的。其他标志位和其他页表硬件结构被定义在 kernel/riscv.h。（译者注：值得一提的是，在 xv6 中，仅有最后一级指向物理地址的 PTE 标志位会设置 RXWU 等。指向下一级页表页的 PTE，其标志位仅有 PTE_V，此特征在 xv6 中用于判断 PTE 是否是最后一级 PTE)。

为了让硬件能使用页表，内核必须将 root 页表页（也就是第一级页表页）的地址写入 satp 寄存器。每个 CPU 有自己的 satp 寄存器。每个 CPU 都会使用他自己的 satp 寄存器来翻译随后的指令以及指令中的地址。每个 CPU 有自己的 satp 才能让不同的 CPU 运行不同的进程，因为每个进程都有自己独有的以页表映射的私有地址空间。

一些术语。物理内存指的是 DRAM 中的存储单元。一个字节的物理内存有一个地址，叫做物理地址。指令只能使用虚拟地址，由页表硬件翻译成物理地址，然后发给 DRAM 硬件进行读写。与`物理内存`，`虚拟地址`不同的是，`虚拟内存`不是实际的物理含义，而是内核提供的一种管理物理内存和虚拟地址的机制手段。

## 内核地址空间
xv6 为每个进程维护一个页表，描述每个进程的用户地址空间，加上一个独立的描述内核地址空间的页表。内核配置地址空间布局以让其能够可预测的访问物理内存和其他硬件资源。下图是xv6 内核内存布局。
![22834193-859410fff007d444.png](https://s2.loli.net/2022/11/03/ENy5kWPlT7jp2Zb.png)

QEMU 模拟的电脑，其物理内存起始地址为 0x80000000 至少终止于 0x86400000 ，这在 xv6 中叫做 PHYSTOP。QEMU 模拟器还包括 I/O 设备例如硬盘接口。QEMU 通过映射他们到 0x8000000 地址以下来暴露这些接口。内核可以通过读写这些特殊的物理地址来与设备交互。这是与物理设备交互而不是RAM。第四章解释了 xv6 是如何与物理设备交互的。

内核使用直接映射的方式获取 RAM 和 内存设备映射。也就是说，映射资源的虚拟地址和物理地址是一致的。在内核内存布局中，左边是 xv6 的内核地址空间，RWX 表示这个 PTE 读写执行权限。右边是 risc-v 期望看见的物理地址空间。

内核在虚拟地址和物理地址上都位于 `KERNBASE=0x80000000`。直接映射简化内核代码读写物理内存。例如，当 fork 为子进程分配用户内存时，分配器返回内存的物理地址；当拷贝父进程的用户内存时，fork 直接将这个地址作为虚拟地址使用。有一些内核的地址不是直接映射的：
- Trampoline Page: 被映射在虚拟地址的高位；用户页表也有同样的映射。第四章将讨论 Trampoline Page，但我们能在这里看到一个页表的一个有趣的使用；一个包含 Trampoline Code 的物理页被映射到虚拟地址两次，一次在虚拟地址顶部一次直接映射。
- 内核栈页：每个进程都它自己的被映射在高位的内核栈， xv6 还在栈下留下未映射的 `guard page 保护页`。保护页的 PTE 是无效的（PTE_V 未设置），这样如果内核溢出到内核栈，将会引起例外内核会崩溃。如果没有保护页，栈溢出将覆盖其他的内核内存区域，造成错误的操作。这样的异常崩溃是良性的。

虽然内核使用高地址映射堆栈，但内核也可以通过直接映射地址访问他们。另一种设计只有直接映射并用直接映射使用。但那样的话，提供保护页必须不再映射虚拟地址，否则这些地址对应的的物理地址不太方便使用。

内核为 `Trampoline` 和 `Kernel Text` 以 TPE_R 和 PTE_X 的权限进行映射。内核从这些页里读取并执行指令。内核以 PTE_R 和 PTE_W 的权限映射其他页，这样能够在这些页内进行读写。对保护页的映射是不允许的。

## Code: 创建一个地址空间
大多数操作地址空间和页表的代码分布在 `vm.c （kernel/vm.c）` 文件中。 核心数据结构 `pagetable_t`，是一个指向 RISC_V 根页表页的指针；一个 pagetable_t 要么是一个内核页表，要么是一个进程页表。核心函数是 `walk`，它为虚拟地址查找 PTE 和 mappages，mappage 用于创建新的虚拟地址到物理地址的映射。以 kvm 开头的函数操作内核页表。以 uvm 开头的函数操作用户页表。其他函数用于这两者。 `copyout` 和 `copyin` 用于拷贝来自用户地址的数据。这两个函数位于 `vm.c` 中因为它们需要进行地址翻译以找到对应的物理地址。

在早期的启动流程中， `main`调用 `kvminit` 创建内核页表。这个调用发生在 xv6 在 RISC-V 上启用页表之前，此时所有地址是直接指向物理内存的。`kvminit`首先分配一页物理内存来装载根页表页。然后调用 kvmmap 映射内核需要的翻译内容，这些内容包括内核指令和数据，物理内存到 PHYSTOP和设备内存分布。

`kvmmap` 调用 `mappages`将虚拟地址范围和物理地址范围的映射安装到页表中。它以页为单位，对每一页进行映射。对于每个被映射的虚拟地址，`mappages` 调用 `walk` 查找他的 PTE 地址。然后初始化 PTE 来装载物理页表地址，以及一些权限来标志 PTE 可用。

walk 行为类似 RISC-V 页表硬件因为它查找一个虚拟地址的 PTE。walk 在3级也表中一次步进 9 位。它使用每一级的 9 位虚拟地址来查找下一级或者最后页的PTE。如果 PTE 是无效的，表示需要的页还没有分配。如果设置了 alloc 参数，walk 分配一个新的页表页并将其物理地址写入 PTE。它返回树中最底层的 PTE 的地址。

以上代码依赖物理内存直接映射到内核虚拟地址空间。例如当 walk 步进页表时，从PTE 中获取下一级的物理地址，然后将其作为虚拟地址获取下一级 PTE 的虚拟地址。

`main` 调用 `kvminithart(kernel/vm.c)` 安装内核页表。它将物理根页表的物理地址写入 `satp` 寄存器。后续CPU会使用内核页表进行地址翻译。由于内核使用个直接映射，下一条指令的虚拟地址将会被正确的映射到物理地址上。

`procinit(kernel/proc.c)` 是被 `main` 函数调用的，为每一个进程分配内核栈。它将每个内核栈映射到由 KSTACK 生成的虚拟地址上，并为无效的堆栈保护页留下空间。`kvmmap` 将映射的 PTEs 添加到内核页表，然后调用 `kvminithart` 重新装载内核页表到 `satp`，这样硬件就知道了新的 PTEs。

每个 RISC-V CPU 缓存页表块在 `Translation Look-aside Buffer (TLB)` 中，当 xv6 修改了页表时，必须告诉 CPU 以使相应的 TLB 缓存失效。如果不那么做的话，后续 TLB 可能会使用旧的缓存映射，同时指向贝其他进程分配的地址，结果，一个进程污染另一个进程的内存。RISC-V 有 `sfence.vma` 指令刷新 CPU 的 TLB 表。当重新加载 `satp` 后，xv6 在 `kvminithart` 中调用 `sfence.vma ` 指令，在返回用户空间之前切换用户页表时也调用该指令。

## 物理内存分配
内核必须在运行期间为页表，用户内存，内核栈和管道缓冲区分配和释放物理内存。
xv6 使用内核代码结束地址和 PHYSTOP 区域用于运行时分配。每次分配整个 4096字节的页。通过一个列表标识哪些页面是空闲的，分配就从这个列表中移除这个页面，释放就将该页面添加到页表。

## Code：物理内存分配
分配器代码位于 `kalloc.c(kernel/kalloc.c:1)`。分配器的数据结构是一个可用与分配的物理页列表。每个空闲页列表的元素是一个`struct run`。分配器从哪里获得存取数据结构的内存？它将每个页的 `run` 结构存在空闲页本身中，因为这没有其他需要存的东西。空闲列表由 spin lock 保护。这个列表和锁被包装在一个结构体里以表示锁保护结构提内的字段。现在，忽略锁的细节，第六章将会解释。

`main` 函数调用 `kinit` 初始化分配器。`kinit` 初始化空闲列以保存内核末尾和 PHYSTOP 之间的每一页。xv6 应该通过硬件提供的配置信息决定有多少物理内存可用。否则 xv6 认为机器有 128 MB 的 RAM。`kinit` 调用 `freerange` 添加内存到空闲列表。一个 PTE 仅能指向 4096 字节对其的物理地址，所以 `freerange` 使用 `PGROUNDUP` 确保空闲列表是物理对齐的。分配器一开始没有内存，调用 `kfree` 进行物理内存初始化，并将内存交给它进行管理。

分配器有时将地址视为整数以便进行数学运算（例如在 `freerange` 里遍历所有页），有时将地址用作指针以进行读写内存（例如操作在每个存储run 结构的页）；这两种使用是分配器代码有大量 c 类型转换的原因。另一种原因是释放和分配改变了内存类型。

`kfree` 函数将释放的每个字节都置为1。这样使用释放后内存的代码读取到的是无效数据而不是旧的信息，希望这能让这些代码更快的中断。然后 `kfree` 将该页作为表头前置，其具体步骤是，将 `pa` 转换成一个 `struct run` 结构体，将 `r->next` 指向旧表头，并将 r.kalloc 设置为空闲列表并返回列表的第一个元素。

## 进程地址空间
每个进程都独立的页表，当 xv6 进行进程切换时，同时也会切换页表。如图 2.3, 进程的用户内存地址从 0 开始并且能增长到 MAXVA，原则上允许进程寻址 256G 字节的地址空间。
![22834193-b5419f00dd561894.png](https://s2.loli.net/2022/11/03/R93QTvmPOLdNzai.png)

当一个进程向 xv6 索要更多的的用户内存时，xv6 首先使用 kalloc 分配物理内存，然后将 PTEs 添加到进程的页表中并指向新分配的物理页。xv6 在这些 PTEs 中设置 PTE_W,PTE_X,PTE_R,PTE_U 和 PTE_V s标志。大多数进程不使用整个用户地址空间，xv6 在将不使用的 PTEs 中清楚其 PTE_V 标志。

我们可以看到一些非常好的使用页表的例子。第一点，不同你进程的页表会将他们的用户地址翻译到不同的物理内存中，这样每个进程都有他们私有的地址空间。第二点，每个进程看到的地址都是从0开始的连续地址，但事实上物理地址可能不是连续的。第三点，内核使用 `trampoline code` 在每个用户地址顶部映射一个页，因此一个物理页出现在每个地址空间。

图 3.4 展示了xv6 中用户地址布局。栈是一个单独的页，展示的是由 exec 创建初始内容。包含命令行的字符串参数以及指向他们的位于栈顶的数组。如果函数 `main` 刚刚被调用，那在其下方是允许程序执行的值。

为了检测用户栈溢出，xv6 在栈下放置了一个失效保护页。如果用户地址溢出，进程试图使用栈下的地址，硬件会产生一个因为无效映射而产生的页错误。一个真实操作系统可能会分配更多的内存给栈使用。

## Code: sbrk
`Sbrk` 是为进程缩小或增加内存的系统调用。这个系统调用基于 `growproc` 实现。`grocprow` 调用 `uvmalloc` 还是 `uvmdealloc`  取决于 `n` 的正负。`uvmalloc` 通过 `kalloc` 分配物理内存，通过 `mappages` 添加 PTEs 到用户页表中。`uvdealloc` 调用 `uvmunmap`，这使用 `walk`  查找 PTEs 并用 `kfree` 释放物理内存。

xv6 使用进程页表其功能不仅仅是告诉硬件如何映射用户虚拟地址，还作为唯一记录哪个物理内存页被分配到进程中。这也是为什么释放用户内存需要查询用户页表。

## Code: exec
`Exec` 是一个创建用户部分地址空间的系统调用。从文件系统中的一个文件初始化用户部分的地址空间。`Exec` 使用 `namei `打开名为 `path` 的二进制文件，这将在第八章解释。然后，它读取 ELF 头。xv6 使用的是被广泛使用的 ELF 格式，定义在 `kernnel/elf.h`。ELF 二进制扩 `ELF头`，`elfhdr 结构`，然后是一系列程序节头，`proghdr 结构`。每个 `proghdr` 描述描述一段应用程序需要被载入内存的数据。xv6程序仅仅只有一个程序头，但是其他系统可能会区分指令和数据。

第一步是快速检查文件是否包含 ELF 二进制。一个 ELF 二进制由魔法数字 `0X7F， ’E‘ ，’L‘，’F‘` 开始。如果 ELF 头正确包含魔法数字，exec 认为这个二进制是格式正确的。

`Exec` 使用 `proc_pagetable` 为没有用户映射分配的分配新页表，使用 `uvmalloc` 为每个 ELF 段分配内存，使用 `loadseg` 加载每个段到内存中。`loadseg` 使用 `walkaddr`查找为每个 ELF 段准备写入的物理地址。使用 `readi` 从文件读取。
`init` 程序的段如下

程序段头的 `filesz` 可能小于 `memsz`，表明中间的空隙应该用 0 填满。对 init 程序来说，`filesz` 是 2112 字节并且 `memsz` 是 2136 字节，因此 `uvmalloc` 分配足够的能容纳 2136 字节的物理内存，但仅仅从 init 中读取 2112 字节。

现在 `exec` 分配和初始化用户栈。它只分配一个栈页。`Exec` 依次拷贝参数字符串到栈顶，将指针记录在 `ustack` 中。然后在末尾放置一个空指针将来传递 `argv` 给 `main` 函数。前三个块是程序返回值，argc 和  argv 指针。

`Exec`在堆栈页的下方放置一个不可访问的页，这样当程序尝试访问多于一个页的内容时就会发生错误。这个不可访问的页允许 `exec` 处理大的参数。在这个解决方案里，`exec`使用的`copyout`函数拷贝参数到栈时会注意到目标页不可访问并返回 -1。

在准备新的内存镜像期间，如果 `exec` 检测到类似程序段错误的问题，将会跳到 `bad` 标志并返回 -1。`exec`必须等待释放旧的镜像知道系统调用完成。如果旧的镜像消失了，系统调用不能返回 -1。唯一的造成 `exec` 错误的原因是创建镜像期间发生错误。一旦镜像创建完成，`exec` 提交新的也表并释放旧的。

`Exec` 从ELF 文件加载字节到内存的指定位置，该位置在 ELF 文件中指定。用户或者进程能在 ELF 文件中覆盖任意地址。因此 `exec` 是有风险的，因为 ELF 文件中的地址可能有意或无意的指向内核。结果可鞥造成内核隔离机制的崩溃。xv6 做了一个数字检查来避免这种风险。例如 `if(ph.vaddr + ph.memsz < ph.vaddr)` 检查加法溢出。这个危险是用户可能构造了一个 ELF 二进制，它的 `ph.vaddr` 只想用户选择的地址，而 `ph.memsz` 大于加法溢出到 0x1000，这将被认为是有效值。旧版本的 xv6 中用户地址空间包含内核（但在用户模式下不可读写），用户能够修改内核内存并将 ELF 数据拷贝到内核。在 risc-v 的 xv6 上这不会发生，因为内核有自己独立的页表。`loadseg` 加载到进程的页表而不是内核的。
内核的开发者很容易忽略这些重要的检查。现实的内核也有很长的历史时期缺少这些检查，而能让用户程序获取内核权限。就像 xv6 并没有对用户提交到内核的数据做完整的数据检验工作，这可能让一个恶意的程序攻破 xv6 的分区隔离。

## Real world
和大多数操作系统一样，xv6 使用页表硬件进行内存保护和映射。大多数操作系统使用比 xv6 更复杂页表来组合页表和页错误例外，这将在第四章进行讨论。

xv6 简单的使用内核虚拟地址和物理地址的直接映射。并假设物理 RAM 在 0x8000000，内核会加载在这里。这在 QEMU 是好的，但在真实的硬件上这不是个好主意。真是的物理RAM和设备在物理地址上是不可预测的，所以可能没有 0x8000000 的 RAM 让内核加载。更严格的内核设计是利用页表将任意物理内存布局映射成可预测的虚拟内核地址布局。

RISC-V 支持物理地址保护，但 xv6 没有使用这个特性。

在有更多内存的机器上，让 RISC-V 支持 `super pages` 是有意义的。`small pages` 在物理内存小的时候更有意义， 能在更细粒度上分配和页输出到磁盘。例如，如果一个程序仅仅使用 8 KB 内存，给它整个 4MB 的物理内存是浪费的。更大的页在更多 RAM 上有意义，减少页表操作的开销。

xv6 的内核缺少类似 `malloc` 的动态分配小对象的分配器。这阻止了内核为动态分配器配套的复杂数据结构。

内存分配一直是一个热门话题，其基本问题是如何有效使用有限的内存和应对未知的请求。今天人们更关注速度而不是空间效率。除此之外，一个精心制作的内核应该能够分配不同大小的小块而不是像xv6 一样只能分配 4096 字节的块。一个真正的内核的分配器能够像处理大块一样处理小块。

## 练习
1.  解析 RISC-V 的设备树以找到计算机拥有的物理内存量。
2.  写一个用户程序，使用 `sbrk` 增长他的地址空间。运行这个程序，并在调用 sbrk 前后分别打印页表。
3. 修改 xv6 在内核中使用 `super pages`
4. 修改 xv6 当用户程序取消一个空指针的引用时，收到例外。也就是说，修改 xv6，让虚拟地址 0 不被映射到用户程序中。
5. Unix 传统上实现 `exec` 包括对 shell 脚本的特殊处理，如果一个文件以 `#!` 开头，第一行被当做一个程序来解释这个文件。例如，如果 `exec` 运行 `myprog arg1` 并且 `myprog` 的第一行是 `#!/interp`，exec 将会运行 `interp` myprog args1。在 xv6 中实现这个约定的支持。
6. 实现内核随机地址空间。