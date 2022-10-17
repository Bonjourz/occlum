use async_rt::wait::Waiter;
use std::ptr::NonNull;

use super::{
    FileTableRef, FsViewRef, NiceValueRef, ProcessRef, ProcessVM, ProcessVMRef, ResourceLimitsRef,
    RobustListHead, SchedAgentRef, SigQueues, SigSet, Thread, ThreadId, ThreadInner, ThreadName,
    ThreadRef,
};
use crate::prelude::*;

#[derive(Debug)]
pub struct ThreadBuilder {
    // Mandatory field
    tid: Option<ThreadId>,
    process: Option<ProcessRef>,
    vm: Option<ProcessVMRef>,
    // Optional fields
    fs: Option<FsViewRef>,
    files: Option<FileTableRef>,
    sched: Option<SchedAgentRef>,
    nice: Option<NiceValueRef>,
    rlimits: Option<ResourceLimitsRef>,
    sig_mask: Option<SigSet>,
    clear_ctid: Option<NonNull<pid_t>>,
    robust_list: Option<NonNull<RobustListHead>>,
    name: Option<ThreadName>,
}

impl ThreadBuilder {
    pub fn new() -> Self {
        Self {
            tid: None,
            process: None,
            vm: None,
            fs: None,
            files: None,
            sched: None,
            nice: None,
            rlimits: None,
            sig_mask: None,
            clear_ctid: None,
            robust_list: None,
            name: None,
        }
    }

    pub fn tid(mut self, tid: ThreadId) -> Self {
        self.tid = Some(tid);
        self
    }

    pub fn process(mut self, process: ProcessRef) -> Self {
        self.process = Some(process);
        self
    }

    pub fn vm(mut self, vm: ProcessVMRef) -> Self {
        self.vm = Some(vm);
        self
    }

    pub fn fs(mut self, fs: FsViewRef) -> Self {
        self.fs = Some(fs);
        self
    }

    pub fn files(mut self, files: FileTableRef) -> Self {
        self.files = Some(files);
        self
    }

    pub fn sig_mask(mut self, sig_mask: SigSet) -> Self {
        self.sig_mask = Some(sig_mask);
        self
    }

    pub fn sched(mut self, sched: SchedAgentRef) -> Self {
        self.sched = Some(sched);
        self
    }

    pub fn nice(mut self, nice: NiceValueRef) -> Self {
        self.nice = Some(nice);
        self
    }

    pub fn rlimits(mut self, rlimits: ResourceLimitsRef) -> Self {
        self.rlimits = Some(rlimits);
        self
    }

    pub fn clear_ctid(mut self, clear_tid_addr: NonNull<pid_t>) -> Self {
        self.clear_ctid = Some(clear_tid_addr);
        self
    }

    pub fn robust_list(mut self, robust_list_addr: NonNull<RobustListHead>) -> Self {
        self.robust_list = Some(robust_list_addr);
        self
    }

    pub fn name(mut self, name: ThreadName) -> Self {
        self.name = Some(name);
        self
    }

    pub fn build(self) -> Result<ThreadRef> {
        let tid = self.tid.unwrap_or_else(|| ThreadId::new());
        let clear_ctid = RwLock::new(self.clear_ctid);
        let robust_list = RwLock::new(self.robust_list);
        let inner = SgxMutex::new(ThreadInner::new());
        let process = self
            .process
            .ok_or_else(|| errno!(EINVAL, "process is mandatory"))?;
        let vm = self
            .vm
            .ok_or_else(|| errno!(EINVAL, "memory is mandatory"))?;
        let fs = self.fs.unwrap_or_default();
        let files = self.files.unwrap_or_default();
        let sched = self.sched.unwrap_or_default();
        let nice = self.nice.unwrap_or_default();
        let rlimits = self.rlimits.unwrap_or_default();
        let name = RwLock::new(self.name.unwrap_or_default());
        let sig_mask = RwLock::new(self.sig_mask.unwrap_or_default());
        let sig_queues = RwLock::new(SigQueues::new());
        let sig_stack = SgxMutex::new(None);
        let waiter = Waiter::new();

        let new_thread = Arc::new(Thread {
            tid,
            clear_ctid,
            robust_list,
            inner,
            process,
            vm,
            fs,
            files,
            sched,
            nice,
            rlimits,
            name,
            sig_queues,
            sig_mask,
            sig_stack,
            waiter,
        });

        let mut inner = new_thread.process().inner();
        inner.threads_mut().unwrap().push(new_thread.clone());
        drop(inner);

        Ok(new_thread)
    }
}
