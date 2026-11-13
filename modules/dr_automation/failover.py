"""
StockMind DR Automated Failover Lambda
Triggered by EventBridge when Route53 health check alarm fires.
Scales ECS services from 0 → desired, starts the TimescaleDB EC2.
"""
import os
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DR_REGION           = os.environ["DR_REGION"]
ECS_CLUSTER         = os.environ["ECS_CLUSTER"]
TIMESCALE_INSTANCE  = os.environ["TIMESCALE_INSTANCE_ID"]
SNS_TOPIC_ARN       = os.environ["SNS_TOPIC_ARN"]
SERVICES            = json.loads(os.environ["SERVICES_JSON"])
# SERVICES_JSON format: {"frontend":{"name":"...", "desired":2}, ...}

ecs = boto3.client("ecs",  region_name=DR_REGION)
ec2 = boto3.client("ec2",  region_name=DR_REGION)
sns = boto3.client("sns",  region_name=DR_REGION)


def handler(event, context):
    logger.info("DR failover triggered. Event: %s", json.dumps(event))

    alarm_state = (
        event.get("detail", {}).get("state", {}).get("value", "ALARM")
    )
    if alarm_state != "ALARM":
        logger.info("Alarm state is %s — no action needed.", alarm_state)
        return {"status": "no-op", "reason": f"alarm state is {alarm_state}"}

    errors = []

    # 1. Start TimescaleDB EC2
    try:
        logger.info("Starting TimescaleDB EC2 instance %s", TIMESCALE_INSTANCE)
        ec2.start_instances(InstanceIds=[TIMESCALE_INSTANCE])
        waiter = ec2.get_waiter("instance_running")
        waiter.wait(
            InstanceIds=[TIMESCALE_INSTANCE],
            WaiterConfig={"Delay": 15, "MaxAttempts": 20},
        )
        logger.info("TimescaleDB instance is running.")
    except Exception as e:
        errors.append(f"EC2 start failed: {e}")
        logger.error("Failed to start TimescaleDB: %s", e)

    # 2. Scale ECS services
    for svc_key, svc_cfg in SERVICES.items():
        svc_name = svc_cfg["name"]
        desired  = int(svc_cfg["desired"])
        try:
            logger.info("Scaling %s → %d", svc_name, desired)
            ecs.update_service(
                cluster=ECS_CLUSTER,
                service=svc_name,
                desiredCount=desired,
            )
            logger.info("Scaled %s to %d", svc_name, desired)
        except Exception as e:
            errors.append(f"ECS scale {svc_name} failed: {e}")
            logger.error("Failed to scale %s: %s", svc_name, e)

    # 3. Notify via SNS
    status  = "ERROR" if errors else "SUCCESS"
    message = (
        f"StockMind DR Failover — {status}\n\n"
        f"Region: {DR_REGION}\n"
        f"TimescaleDB: {TIMESCALE_INSTANCE}\n"
        f"ECS Cluster: {ECS_CLUSTER}\n"
    )
    if errors:
        message += "\nErrors:\n" + "\n".join(f"  • {e}" for e in errors)
    else:
        message += "\nAll services started successfully. DNS will auto-failover via Route53."

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[StockMind DR] Failover {status}",
            Message=message,
        )
    except Exception as e:
        logger.error("SNS publish failed: %s", e)

    return {"status": status, "errors": errors}
