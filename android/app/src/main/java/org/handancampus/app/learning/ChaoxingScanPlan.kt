package org.handancampus.app.learning

object ChaoxingScanPlan {
    fun select(courses:List<LearningCourse>,selected:Set<String>,stamps:Map<String,Long>,force:Boolean,now:Long):List<LearningCourse> =
        courses.filter { it.key in selected && (force || now-(stamps[it.key] ?: 0L)>=600000L) }.distinctBy { it.key }
}
