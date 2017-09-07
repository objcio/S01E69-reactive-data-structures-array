import ReactiveSwift
import Foundation


enum List<A> {
    case empty
    indirect case cons(A, List<A>)
}

extension List {
    func reduce<B>(_ initial: B, _ combine: (B, A) -> B) -> B {
        switch self {
        case .empty:
            return initial
        case let .cons(value, tail):
            let intermediate = combine(initial, value)
            return tail.reduce(intermediate, combine)
        }
    }
}

//let list: List<Int> = .cons(1, .cons(2, .cons(3, .empty)))
//list.reduce(0, +)

enum RList<A> {
    case empty
    indirect case cons(A, MutableProperty<RList<A>>)
}

extension RList {
    init(array: [A]) {
        self = .empty
        for element in array.reversed() {
            self = .cons(element, MutableProperty(self))
        }
    }
    
    func reduce<B>(_ initial: B, _ combine: @escaping (B, A) -> B) -> Property<B> {
        let result = MutableProperty(initial)
        func reduceH(list: RList<A>, intermediate: B) {
            switch list {
            case .empty:
                result.value = intermediate
            case let .cons(value, tail):
                let newIntermediate = combine(intermediate, value)
                tail.signal.observeValues { newTail in
                    reduceH(list: newTail, intermediate: newIntermediate)
                }
                reduceH(list: tail.value, intermediate: newIntermediate)
            }
        }
        reduceH(list: self, intermediate: initial)
        return Property(result)
    }
    
}

func append<A>(_ value: A, to list: MutableProperty<RList<A>>) {
    switch list.value {
    case .empty:
        list.value = .cons(value, MutableProperty(.empty))
    case .cons(_, let tail):
        append(value, to: tail)
    }
}

enum ArrayChange<A> {
    case insert(A, at: Int)
    case remove(at: Int)
}

extension Array {
    mutating func apply(_ change: ArrayChange<Element>) {
        switch change {
        case let .insert(value, idx):
            insert(value, at: idx)
        case let .remove(idx):
            remove(at: idx)
        }
    }
    
    func applying(_ change: ArrayChange<Element>) -> [Element] {
        var copy = self
        copy.apply(change)
        return copy
    }
    
    func filteredIndex(for index: Int, _ isIncluded: (Element) -> Bool) -> Int {
        var skipped = 0
        for i in 0..<index {
            if !isIncluded(self[i]) {
                skipped += 1
            }
        }
        return index - skipped
    }
}

struct RArray<A> {
    let initial: [A]
    let changes: Property<RList<ArrayChange<A>>>
    
    var latest: Property<[A]> {
        return changes.flatMap(.latest) { changeList in
            changeList.reduce(self.initial) { $0.applying($1) }
        }
    }
    
    static func mutable(_ initial: [A]) -> (RArray<A>, appendChange: (ArrayChange<A>) -> ()) {
        let changes = MutableProperty<RList<ArrayChange<A>>>(RList(array: []))
        let result = RArray(initial: initial, changes: Property(changes))
        return (result, { change in append(change, to: changes)})
        
    }
    
    func filter(_ isIncluded: @escaping (A) -> Bool) -> RArray<A> {
        let filtered = initial.filter(isIncluded)
        let (result, addChange) = RArray.mutable(filtered)
        func filterH(_ latestChanges: RList<ArrayChange<A>>) {
            latestChanges.reduce(self.initial) { intermediate, change in
                switch change {
                case let .insert(value, idx) where isIncluded(value):
                    let newIndex = intermediate.filteredIndex(for: idx, isIncluded)
                    addChange(.insert(value, at: newIndex))
                case let .remove(idx) where isIncluded(intermediate[idx]):
                    let newIndex = intermediate.filteredIndex(for: idx, isIncluded)
                    addChange(.remove(at: newIndex))
                default: break
                }
                return intermediate.applying(change)
            }
            
        }
        changes.signal.observeValues(filterH)
        filterH(changes.value)
        return result
    }
}

let (arr, addChange) = RArray.mutable([1,2,3])
//arr.latest.signal.observeValues { print($0) }
addChange(.insert(4, at: 3))
arr.latest.value
let filtered = arr.filter { $0 % 2 == 0 }
filtered.latest.signal.observeValues { print($0) }
addChange(.insert(5, at: 4))
addChange(.insert(6, at: 5))
