import Foundation

struct TimelineArchive: Sendable {
    var markdown: String
    var photos: [String: Data]
    var files: [String: Data] {
        var result = photos
        result["archive.md"] = Data(markdown.utf8)
        return result
    }
    func zipData() throws -> Data { try TimelineZIP.encode(files) }
}

enum TimelineMarkdown {
    /// Escape user content so names/notes cannot manufacture links or archive paths.
    static func escape(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        for character in ["\\", "`", "*", "_", "[", "]", "<", ">", "#", "|"] {
            value = value.replacingOccurrences(of: character, with: "\\" + character)
        }
        return value
    }
    static func generate(history: TimelineHistory, interval: DateInterval?, calendar: Calendar, asOf: Date) -> TimelineArchive {
        let days = GrowthTimeline.days(history: history, interval: interval, calendar: calendar, asOf: asOf)
        var lines = ["# " + L10n.text("Growth Timeline"), "", L10n.text("Private local archive. Nutrition adherence uses current targets; missing records are not zeros."), ""]
        var photos: [String: Data] = [:]
        if let interval {
            lines += ["\(GrowthTimeline.dateKey(interval.start, calendar: calendar)) – \(GrowthTimeline.dateKey(calendar.date(byAdding: .day, value: -1, to: interval.end)!, calendar: calendar))", ""]
            let summary = GrowthTimeline.summary(history: history, interval: interval, calendar: calendar, asOf: asOf)
            lines += ["## " + L10n.text("Period summary"), "", escape(summary.text), ""]
            for exercise in summary.exercises { lines += ["- " + escape(exercise.summary)] }
            lines += [""]
        }
        if days.isEmpty { lines += [L10n.text("No records in this period."), ""] }
        func numeric(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) }
        for day in days {
            let date = GrowthTimeline.dateKey(day.date, calendar: calendar)
            lines += ["# \(date)", "", "## " + L10n.text("Body"), ""]
            if let weight = day.weight { lines += [L10n.text("Weight: %@ kg", numeric(weight))] }
            else { lines += [L10n.text("Not logged")] }
            if let average = day.weightAverage {
                lines += [L10n.text("7-day average: %@ kg (%@ weigh-ins)", numeric(average), String(day.weightSampleCount))]
            }
            lines += ["", "## " + L10n.text("Sleep"), "", day.sleep.map { L10n.text("%@ h", numeric($0)) } ?? L10n.text("No readable Health sleep"), "", "## " + L10n.text("Nutrition"), ""]
            if day.meals.isEmpty { lines += [L10n.text("Not logged"), ""] }
            for meal in day.meals {
                lines += ["### \(meal.category.label): \(escape(meal.name))", "", meal.date.formatted(date: .omitted, time: .shortened), ""]
                if let photo = meal.photo {
                    let path = "photos/\(date)-meal-\(meal.id.uuidString.lowercased()).jpg"
                    photos[path] = photo
                    lines += ["![\(escape(meal.name))](\(path))", ""]
                }
                for food in meal.foods {
                    lines += ["- " + L10n.text("%@ · %@ g · %@ kcal · P %@ / C %@ / F %@ g", escape(food.name), numeric(food.grams), numeric(food.calories), numeric(food.protein), numeric(food.carbs), numeric(food.fat))]
                    if let confidence = food.confidence { lines += ["  " + L10n.text("Confidence: %@", numeric(confidence))] }
                    if !food.notes.isEmpty { lines += ["  " + escape(food.notes)] }
                }
                lines += ["", L10n.text("Calories: %@ kcal · Protein: %@ g · Carbs: %@ g · Fat: %@ g", numeric(meal.calories), numeric(meal.protein), numeric(meal.carbs), numeric(meal.fat)), ""]
            }
            if !day.meals.isEmpty { lines += [L10n.text("Daily totals: %@ kcal · %@ g protein · %@ g carbs · %@ g fat", numeric(day.calories), numeric(day.protein), numeric(day.carbs), numeric(day.fat)), ""] }
            lines += ["## " + L10n.text("Gym"), ""]
            if day.workouts.isEmpty { lines += [L10n.text("None logged"), ""] }
            for workout in day.workouts {
                lines += ["### " + escape(workout.name), ""]
                for exercise in workout.exercises {
                    lines += ["#### " + escape(exercise.name), "", "- " + L10n.text("%@ kg × %@ reps × %@ sets · RPE %@", numeric(exercise.weight), String(exercise.reps), String(exercise.sets), numeric(exercise.rpe))]
                    if !exercise.notes.isEmpty { lines += ["- " + escape(exercise.notes)] }
                    lines += [""]
                }
            }
            lines += ["## " + L10n.text("Badminton"), "", day.badminton ? L10n.text("Badminton logged") : L10n.text("None logged"), "", "## " + L10n.text("Progress Photos"), ""]
            for photo in day.photos {
                let path = "photos/\(date)-\(photo.angle.rawValue)-\(photo.id.uuidString.lowercased()).jpg"
                photos[path] = photo.data
                lines += ["![\(photo.angle.label)](\(path))", "", escape(photo.notes), ""]
            }
            if day.photos.isEmpty { lines += [L10n.text("None logged"), ""] }
            if !day.milestones.isEmpty {
                lines += ["## " + L10n.text("Milestones"), ""]
                for milestone in day.milestones { lines += ["- \(escape(milestone.title)): \(escape(milestone.detail))"] }
                lines += [""]
            }
            lines += ["## " + L10n.text("Daily Summary"), "", escape(day.summary), ""]
        }
        return TimelineArchive(markdown: lines.joined(separator: "\n"), photos: photos)
    }
}

// A standard ZIP (stored entries). JPEGs are already compressed; no third-party library
// or shell utility is required on iOS. Paths are controlled by the exporter.
enum TimelineZIP {
    enum ArchiveError: Error, LocalizedError {
        case tooLarge, invalidPath
        var errorDescription: String? {
            switch self {
            case .tooLarge: return L10n.text("This archive exceeds the ZIP limit. Export a shorter period or omit photos.")
            case .invalidPath: return L10n.text("The archive contains an invalid photo path.")
            }
        }
    }
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }
    private static func crc32(_ data: Data) throws -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for (index, byte) in data.enumerated() {
            if index % 65536 == 0 { try Task.checkCancellation() }
            crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
    static func encode(_ files: [String: Data]) throws -> Data {
        try Task.checkCancellation()
        guard files.count < Int(UInt16.max) else { throw ArchiveError.tooLarge }
        var output = Data(), central = Data()
        func word(_ value: UInt16, into data: inout Data) {
            data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func long(_ value: UInt32, into data: inout Data) {
            for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        for path in files.keys.sorted() {
            try Task.checkCancellation()
            guard !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains(".."), !path.isEmpty else { throw ArchiveError.invalidPath }
            let name = Data(path.utf8), contents = files[path]!
            guard name.count < Int(UInt16.max), contents.count < Int(UInt32.max), output.count < Int(UInt32.max),
                  UInt64(output.count) + UInt64(contents.count) + UInt64(name.count) + 30 < UInt64(UInt32.max) else { throw ArchiveError.tooLarge }
            let offset = UInt32(output.count), size = UInt32(contents.count), crc = try crc32(contents)
            long(0x04034b50, into: &output); word(20, into: &output); word(0x800, into: &output)
            word(0, into: &output); word(0, into: &output); word(0x21, into: &output)
            long(crc, into: &output); long(size, into: &output); long(size, into: &output)
            word(UInt16(name.count), into: &output); word(0, into: &output)
            output.append(name); output.append(contents)
            long(0x02014b50, into: &central); word(20, into: &central); word(20, into: &central); word(0x800, into: &central)
            word(0, into: &central); word(0, into: &central); word(0x21, into: &central)
            long(crc, into: &central); long(size, into: &central); long(size, into: &central)
            word(UInt16(name.count), into: &central)
            for _ in 0..<4 { word(0, into: &central) }
            long(0, into: &central); long(offset, into: &central); central.append(name)
        }
        guard UInt64(output.count) + UInt64(central.count) + 22 < UInt64(UInt32.max) else { throw ArchiveError.tooLarge }
        let centralOffset = UInt32(output.count); output.append(central)
        long(0x06054b50, into: &output); word(0, into: &output); word(0, into: &output)
        word(UInt16(files.count), into: &output); word(UInt16(files.count), into: &output)
        long(UInt32(central.count), into: &output); long(centralOffset, into: &output); word(0, into: &output)
        return output
    }
}
