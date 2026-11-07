package org.handancampus.app.learning

import org.json.JSONObject

/** Explicit allowlist: signed URL, cpi, cookies and authentication material stay native. */
object ChaoxingBridge {
    fun record(item:LearningRecord):JSONObject = JSONObject().put("id",item.id).put("courseId",item.courseId).put("classId",item.classId).put("workId",item.workId).put("kind",item.kind).put("title",item.title).put("course",item.course).put("status",item.status).put("statusText",item.statusText).put("deadline",item.deadline ?: JSONObject.NULL).put("startAt",item.startAt ?: JSONObject.NULL).put("timeText",item.timeText).put("description",item.description).put("hasLink",true)
}
