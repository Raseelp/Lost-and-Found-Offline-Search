package dev.raseel.lostandfound.embedder.memories

/**
 * What the daily notification is about. Every kind is warm: what you have, never what is missing.
 *
 * Some are tied to a date or to a thing that just happened (the "special" ones: a first anniversary, a
 * round number of photos); the rest are there any day there is something good to say.
 */
enum class MemoryKind(val code: String, val label: String, val special: Boolean = false) {
    ANNIVERSARY("anniversary", "ANNIVERSARY", special = true), // two people's first photo together, on its anniversary
    PERSON_ANNIVERSARY("person_anniversary", "FIRST DAY", special = true), // someone's first day in the photos
    MILESTONE("milestone", "MILESTONE", special = true), // someone reaches a round number of photos
    THEN_NOW("then_now", "THEN & NOW"), // a person, first year next to latest
    PAIR_THEN_NOW("pair_then_now", "THEN & NOW, TOGETHER"), // two people together, first year next to latest
    ON_THIS_DAY("on_this_day", "ON THIS DAY"),
    TOGETHER_SINCE("together_since", "TOGETHER"), // two people's years of photos together
    TRIP("trip", "A FEW DAYS"), // a few busy days in a row, in a past year, round this date
    SAME_DAY("same_day", "ACROSS THE YEARS"), // this date in three or more different years
    VAULT("vault", "REMEMBER"), // a lovely picture of someone, out of the blue
    THIS_WEEK("this_week", "THIS WEEK"); // the week round the date, when nothing else is there

    companion object {
        fun fromCode(code: String?): MemoryKind? = entries.firstOrNull { it.code == code }
    }
}

/**
 * The two times of day a memory is sent, and when they are good: the early morning one is the first
 * thing to see, before the day starts (it looks back); the evening one is for settling down (it is about
 * people). Each only makes sense around its own time, so one that runs far too late is skipped.
 */
enum class Slot(val code: String, val hour: Int, val minute: Int, val fromHour: Int, val untilHour: Int) {
    MORNING("morning", 6, 30, 4, 13),
    EVENING("evening", 19, 30, 15, 24);

    companion object {
        fun fromCode(code: String?): Slot = entries.firstOrNull { it.code == code } ?: MORNING
    }
}

object MemoryRotation {

    /** A kind that went out, the day (see [MemoryDays.dayNumber]) and which of the two times. */
    class Used(val kind: MemoryKind, val day: Int, val slot: Slot = Slot.MORNING)

    // The order the ordinary kinds are preferred in when none has been used more recently than another: the
    // morning looks back, the evening is about people.
    private val MORNING = listOf(
        MemoryKind.ON_THIS_DAY, MemoryKind.SAME_DAY, MemoryKind.TRIP, MemoryKind.TOGETHER_SINCE,
        MemoryKind.THEN_NOW, MemoryKind.VAULT, MemoryKind.PAIR_THEN_NOW,
    )
    private val EVENING = listOf(
        MemoryKind.THEN_NOW, MemoryKind.PAIR_THEN_NOW, MemoryKind.TOGETHER_SINCE, MemoryKind.VAULT,
        MemoryKind.TRIP, MemoryKind.ON_THIS_DAY, MemoryKind.SAME_DAY,
    )

    // The special ones that belong to each time; the other time's are taken too if they were missed.
    private val MORNING_SPECIAL = listOf(MemoryKind.ANNIVERSARY, MemoryKind.PERSON_ANNIVERSARY)
    private val EVENING_SPECIAL = listOf(MemoryKind.MILESTONE)

    /**
     * The kind for [slot] today from what is [available], given what went out before: a special one that
     * belongs to this time first; otherwise the kind that has gone longest without (never used counts as
     * longest), in this time's order, and never one that already went out today or that went out
     * yesterday while another is there. "This week" is only the fallback. Null: nothing good.
     */
    fun choose(available: Set<MemoryKind>, history: List<Used>, today: Int, slot: Slot = Slot.MORNING): MemoryKind? {
        val sentToday = history.filter { it.day == today }.map { it.kind }.toSet()
        val there = available - sentToday
        val own = if (slot == Slot.MORNING) MORNING_SPECIAL else EVENING_SPECIAL
        val other = if (slot == Slot.MORNING) EVENING_SPECIAL else MORNING_SPECIAL
        (own + other).firstOrNull { it in there }?.let {
            // The other time's special is only taken in this time when it was missed, which is when it is the only thing there.
            if (it in own || there.none { k -> !k.special && k != MemoryKind.THIS_WEEK }) return it
        }
        val order = if (slot == Slot.MORNING) MORNING else EVENING
        val ordinary = order.filter { it in there }
        if (ordinary.isEmpty()) {
            return (own + other).firstOrNull { it in there } ?: if (MemoryKind.THIS_WEEK in there) MemoryKind.THIS_WEEK else null
        }
        val yesterday = history.filter { today - it.day == 1 }.map { it.kind }.toSet()
        val options = ordinary.filter { it !in yesterday }.ifEmpty { ordinary }
        fun idle(k: MemoryKind): Int = history.lastOrNull { it.kind == k }?.let { today - it.day } ?: Int.MAX_VALUE
        return options.maxWithOrNull(compareBy<MemoryKind> { idle(it) }.thenBy { -order.indexOf(it) })
    }

    /** For "send one now": the next kind that is there, after [last] in the order of the kinds, so every press shows something else. */
    fun chooseForTest(available: Set<MemoryKind>, last: MemoryKind?): MemoryKind? {
        if (available.isEmpty()) return null
        val all = MemoryKind.entries
        val from = if (last == null) 0 else all.indexOf(last) + 1
        for (i in all.indices) {
            val k = all[(from + i) % all.size]
            if (k in available) return k
        }
        return null
    }

    fun encodeHistory(history: List<Used>): String = history.takeLast(HISTORY_KEEP).joinToString(",") { "${it.kind.code}:${it.day}:${it.slot.code}" }

    fun decodeHistory(text: String?): List<Used> {
        if (text.isNullOrBlank()) return emptyList()
        return text.split(',').mapNotNull { part ->
            val bits = part.split(':')
            if (bits.size < 2) return@mapNotNull null
            val kind = MemoryKind.fromCode(bits[0]) ?: return@mapNotNull null
            val day = bits[1].toIntOrNull() ?: return@mapNotNull null
            Used(kind, day, Slot.fromCode(bits.getOrNull(2)))
        }
    }

    private const val HISTORY_KEEP = 28

    // ---- what was shown lately ----

    /** What was shown lately, by photo, as "key=daynumber" entries: the ones from the last [keepDays] days. */
    fun prune(seen: Map<Long, Int>, today: Int, keepDays: Int = KEEP_DAYS): Map<Long, Int> =
        seen.filterValues { today - it in 0 until keepDays }

    /** Keeps the photos not shown lately. */
    fun fresh(keys: List<Long>, seen: Map<Long, Int>): List<Long> = keys.filter { it !in seen }

    const val KEEP_DAYS = 120

    fun encode(seen: Map<Long, Int>): String = seen.entries.joinToString(",") { "${it.key}=${it.value}" }

    fun decode(text: String?): Map<Long, Int> {
        if (text.isNullOrBlank()) return emptyMap()
        val out = HashMap<Long, Int>()
        for (part in text.split(',')) {
            val i = part.indexOf('=')
            if (i <= 0) continue
            val k = part.substring(0, i).toLongOrNull() ?: continue
            val d = part.substring(i + 1).toIntOrNull() ?: continue
            out[k] = d
        }
        return out
    }

    // ---- who it was about lately (a person or a pair is not the subject again for a while) ----

    const val SUBJECT_DAYS = 45

    fun pruneSubjects(subjects: Map<String, Int>, today: Int, keepDays: Int = SUBJECT_DAYS): Map<String, Int> =
        subjects.filterValues { today - it in 0 until keepDays }

    fun encodeSubjects(subjects: Map<String, Int>): String = subjects.entries.joinToString(";") { "${it.key}=${it.value}" }

    fun decodeSubjects(text: String?): Map<String, Int> {
        if (text.isNullOrBlank()) return emptyMap()
        val out = HashMap<String, Int>()
        for (part in text.split(';')) {
            val i = part.lastIndexOf('=')
            if (i <= 0) continue
            out[part.substring(0, i)] = part.substring(i + 1).toIntOrNull() ?: continue
        }
        return out
    }

    /** The subject of a pair of people, the same whichever way round. */
    fun pairSubject(a: Long, b: Long): String = "pair:${minOf(a, b)}-${maxOf(a, b)}"

    fun personSubject(id: Long): String = "p$id"
}
