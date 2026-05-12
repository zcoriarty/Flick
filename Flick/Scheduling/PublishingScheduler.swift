//
//  PublishingScheduler.swift
//  Flick
//

import Foundation

struct PublishingScheduler {
    func transition(_ job: PublishingJob, to nextStatus: PublishingJobStatus, at date: Date = Date()) throws -> PublishingJob {
        guard job.status.canTransition(to: nextStatus) else {
            throw FlickRepositoryError.transitionNotAllowed(from: job.status, to: nextStatus)
        }

        var updated = job
        updated.status = nextStatus
        updated.updatedAt = date
        if nextStatus == .approved {
            updated.approvedAt = date
        }
        if nextStatus == .failed {
            updated.workerDeviceID = nil
            updated.workerLeaseExpiresAt = nil
        }
        return updated
    }

    func claim(_ job: PublishingJob, workerDeviceID: UUID, leaseDuration: TimeInterval, at date: Date = Date()) -> PublishingJob? {
        guard !job.isLeaseActive, !job.status.isTerminal else { return nil }

        var claimed = job
        claimed.workerDeviceID = workerDeviceID
        claimed.workerLeaseExpiresAt = date.addingTimeInterval(leaseDuration)
        claimed.updatedAt = date
        return claimed
    }

    func dueJobs(from jobs: [PublishingJob], at date: Date = Date()) -> [PublishingJob] {
        jobs
            .filter { $0.scheduledAt <= date }
            .filter { !$0.status.isTerminal }
            .filter { !$0.isLeaseActive }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }
}
