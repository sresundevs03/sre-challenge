"""
Expiry Checker Lambda
Se ejecuta diariamente via EventBridge.
Si la fecha actual supera expiry_date, envía alerta por email via SES/SNS.
"""
import boto3
import os
from datetime import datetime, date


def handler(event, context):
    expiry_str = os.environ.get("EXPIRY_DATE", "")
    owner_email = os.environ.get("OWNER_EMAIL", "")
    project = os.environ.get("PROJECT_NAME", "sre-challenge")

    if not expiry_str:
        print("ERROR: EXPIRY_DATE not configured")
        return {"statusCode": 500, "body": "EXPIRY_DATE not configured"}

    try:
        expiry_date = datetime.strptime(expiry_str, "%Y-%m-%d").date()
    except ValueError:
        print(f"ERROR: Invalid EXPIRY_DATE format: {expiry_str}")
        return {"statusCode": 500, "body": "Invalid date format"}

    today = date.today()
    days_remaining = (expiry_date - today).days

    print(f"Project: {project}")
    print(f"Today: {today}")
    print(f"Expiry: {expiry_date}")
    print(f"Days remaining: {days_remaining}")

    # Alerta cuando quedan 3 días o menos
    if days_remaining <= 3:
        sns = boto3.client("sns")
        topic_arn = os.environ.get("SNS_TOPIC_ARN", "")

        if topic_arn:
            urgency = "VENCE HOY" if days_remaining <= 0 else f"vence en {days_remaining} días"
            message = (
                f"ALERTA: Infraestructura {project} {urgency}.\n\n"
                f"Fecha de expiración: {expiry_date}\n"
                f"Hoy: {today}\n\n"
                f"Ejecuta terraform destroy AHORA:\n"
                f"  cd terraform/\n"
                f"  aws s3 rm s3://TU-BUCKET --recursive\n"
                f"  terraform destroy --auto-approve\n"
            )
            sns.publish(
                TopicArn=topic_arn,
                Subject=f"[SRE-CHALLENGE] Infraestructura expira: {expiry_date}",
                Message=message,
            )
            print(f"Alert sent to SNS topic: {topic_arn}")

    return {
        "statusCode": 200,
        "body": {
            "project": project,
            "expiry_date": str(expiry_date),
            "days_remaining": days_remaining,
            "alert_sent": days_remaining <= 3,
        },
    }
