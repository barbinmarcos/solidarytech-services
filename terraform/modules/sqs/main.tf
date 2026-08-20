resource "aws_sqs_queue" "dlq" {
  name = "${var.queue_name}-dlq"

  message_retention_seconds = 1209600

  tags = {
    Name = "${var.queue_name}-dlq"
  }
}

resource "aws_sqs_queue" "main" {
  name = var.queue_name

  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 10

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Name = var.queue_name
  }
}
