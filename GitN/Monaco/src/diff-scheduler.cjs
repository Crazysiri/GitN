// One active request. Terminating superseded work prevents a queue of expensive diffs.
class DiffScheduler {
  constructor(createWorker, deadline = 2500) {
    this.createWorker = createWorker;
    this.deadline = deadline;
    this.sequence = 0;
    this.worker = null;
    this.pending = null;
  }

  cancel() {
    this.sequence += 1;
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.resolve(null);
      this.pending = null;
      this.worker.terminate();
      this.worker = null;
    }
  }

  run(original, modified) {
    this.cancel();
    const id = this.sequence;
    return new Promise((resolve, reject) => {
      try {
        this.worker = this.worker || this.createWorker();
        const finish = (error, result) => {
          if (!this.pending || this.pending.id !== id) return;
          clearTimeout(this.pending.timer);
          this.pending = null;
          if (error) {
            this.worker.terminate();
            this.worker = null;
            reject(error);
          } else {
            resolve(result);
          }
        };
        this.pending = { id, resolve, timer: setTimeout(() => {
          finish(new Error('Diff computation timed out. Text remains available.'));
        }, this.deadline) };
        this.worker.onmessage = ({ data }) => {
          if (data.id !== id) return;
          finish(data.error ? new Error(data.error) : null, data.result);
        };
        this.worker.onerror = () => finish(new Error('Diff worker could not load. Text remains available.'));
        this.worker.postMessage({ id, original, modified });
      } catch (error) {
        if (this.pending) clearTimeout(this.pending.timer);
        this.pending = null;
        if (this.worker) this.worker.terminate();
        this.worker = null;
        reject(error);
      }
    });
  }

  dispose() {
    this.cancel();
    if (this.worker) this.worker.terminate();
    this.worker = null;
  }
}

module.exports = { DiffScheduler };
