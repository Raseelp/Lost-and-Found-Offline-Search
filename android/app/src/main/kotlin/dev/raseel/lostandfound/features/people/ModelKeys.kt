package dev.raseel.lostandfound.features.people

/** Compares the keys that name the pair of face models the stored people were grouped with. */
object ModelKeys {

    /** Whether two keys name the same models. A ".bundled_" prefix is the same model without it. No key names no models. */
    fun same(stored: String?, current: String?): Boolean =
        stored != null && current != null && stored.replace(".bundled_", "") == current

    /**
     * Whether the models in use can work with what is stored. With no key stored yet there are no people to clash
     * with, so any models can be used and the caller saves [current].
     */
    fun usable(stored: String?, current: String?): Boolean =
        current != null && (stored == null || same(stored, current))
}
