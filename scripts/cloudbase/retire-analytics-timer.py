"""Remove only the analytics hourly timer and verify its absence."""
import os
import time

from tencentcloud.common.credential import Credential
from tencentcloud.common.exception.tencent_cloud_sdk_exception import TencentCloudSDKException
from tencentcloud.scf.v20180416 import models, scf_client

NAMESPACE = "hanyuantong-d8gjzt1jh12370215"
FUNCTION = "hyt-analytics-hourly"
TIMER = "hyt-hourly"


def request(model):
    value = model()
    value.FunctionName = FUNCTION
    value.Namespace = NAMESPACE
    return value


def find_timer(client):
    query = request(models.ListTriggersRequest)
    query.Filters = [models.Filter()]
    query.Filters[0].Name = "TriggerName"
    query.Filters[0].Values = [TIMER]
    try:
        result = client.ListTriggers(query)
        triggers = result.Triggers
        if triggers is None or len(triggers) != result.TotalCount:
            raise RuntimeError("Incomplete trigger list")
    except TencentCloudSDKException as error:
        if not any(word in error.get_code() for word in ("Unauthorized", "AuthFailure", "Unsupported")):
            raise
        detail = client.GetFunction(request(models.GetFunctionRequest))
        triggers = detail.Triggers
        if triggers is None:
            raise RuntimeError("Trigger details unavailable")
    return any(item.TriggerName == TIMER and item.Type == "timer" for item in triggers)


def main():
    client = scf_client.ScfClient(Credential(os.environ["TENCENTCLOUD_SECRETID"],
        os.environ["TENCENTCLOUD_SECRETKEY"], os.environ["TENCENTCLOUD_SESSIONTOKEN"]), "ap-shanghai")
    if find_timer(client):
        delete = request(models.DeleteTriggerRequest)
        delete.TriggerName = TIMER
        delete.Type = "timer"
        client.DeleteTrigger(delete)
    for _ in range(15):
        if not find_timer(client):
            print("Verified absent: hyt-analytics-hourly / hyt-hourly")
            return
        time.sleep(2)
    raise RuntimeError("Timer still present")


if __name__ == "__main__":
    main()
