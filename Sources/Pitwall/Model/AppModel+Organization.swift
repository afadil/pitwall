import PitwallCore
import SwiftUI

/// Lanes, tags and hidden cards. Every change lands in organization.json.
extension AppModel {
    func toggleHidden(_ task: BoardTask) {
        if task.isHidden {
            organization.setHidden(false, for: task.id)
            show(.info, "Card shown again")
        } else {
            organization.setHidden(true, for: task.id)
            if selectedTaskID == task.id { selectedTaskID = nil }
            show(.info, "Card hidden. Turn on “Show hidden” to see it.")
        }
    }

    /// Moves a card, and the rest of its stack, to a lane.
    func setLane(_ lane: Lane, for task: BoardTask) {
        let ids = BoardLayout.stackPeers(of: task, in: board.tasks)
        guard ids.contains(where: { (board.task(id: $0)?.lane ?? .normal) != lane }) else { return }
        organization.setLane(lane, for: ids)
        show(.info, ids.count > 1 ? "Moved the stack to \(lane.title)" : "Moved to \(lane.title)")
    }

    func setTag(_ tag: CardTag, on: Bool, for task: BoardTask) {
        organization.setTag(tag.id, on: on, for: task.id)
    }

    func hasTag(_ tag: CardTag, _ task: BoardTask) -> Bool {
        task.tags.contains { $0.id == tag.id }
    }

    /// Creates a tag (or finds one with that name) and adds it to `task` if given.
    @discardableResult
    func createTag(named name: String, color: TagColor? = nil, for task: BoardTask? = nil) -> CardTag? {
        guard let tag = organization.createTag(named: name, color: color) else { return nil }
        if let task { organization.setTag(tag.id, on: true, for: task.id) }
        return tag
    }

    func beginNewTag(for task: BoardTask?) {
        newTagTarget = task
        isNamingNewTag = true
    }

    func deleteTag(_ tag: CardTag) {
        organization.deleteTag(tag.id)
        tagFilter.tagIDs.remove(tag.id)
        show(.info, "Deleted tag “\(tag.name)”")
    }

    /// A drop onto a row moves the cards to the row's lane and, for tag rows, adds the tag.
    func drop(_ taskIDs: [String], on row: BoardRow) {
        for id in taskIDs {
            guard let task = board.task(id: id) else { continue }
            organization.setLane(row.dropLane, for: BoardLayout.stackPeers(of: task, in: board.tasks))
            if let tagID = row.dropTag { organization.setTag(tagID, on: true, for: id) }
        }
    }

    func cardsUsing(_ tag: CardTag) -> Int {
        organization.cards.values.filter { $0.tagIDs.contains(tag.id) }.count
    }
}
