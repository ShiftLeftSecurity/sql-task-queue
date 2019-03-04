-- Copyright 2019 ShiftLeft, Inc.

-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at

--    http://www.apache.org/licenses/LICENSE-2.0

-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

--
-- Name: queue_add_task(text, bytea, bigint, bigint, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_add_task(topic text, data bytea, retries bigint DEFAULT '1'::bigint, priority bigint DEFAULT '0'::bigint, now timestamp with time zone DEFAULT now()) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
  task_id BIGINT;
BEGIN
  INSERT INTO queue_tasks (topic, data, retries_left, priority, added_at)
  VALUES (topic, data, retries, priority, now)
  RETURNING id
  INTO task_id;
  RETURN task_id;
END;
$$;


--
-- Name: queue_cancel_all_tasks(text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_cancel_all_tasks(topic_arg text, now timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE queue_tasks
  SET canceled_at = now
  WHERE topic = topic_arg AND canceled_at IS NULL;
END;
$$;


--
-- Name: queue_cancel_task(bigint, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_cancel_task(task_id bigint, now timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE queue_tasks
  SET canceled_at = now
  WHERE id = task_id AND canceled_at IS NULL;
END;
$$;


--
-- Name: queue_commit_task(bigint, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_commit_task(task_id bigint, consumer_id_arg text, now timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE queue_tasks
  SET committed_at = now
  WHERE id = task_id AND consumer_id = consumer_id_arg;
END;
$$;


--
-- Name: queue_consume_task(text, text, bigint, interval, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_consume_task(topic_arg text, consumer_id_arg text, min_priority bigint DEFAULT '0'::bigint, heartbeat_timeout_arg interval DEFAULT '00:01:00'::interval, now timestamp with time zone DEFAULT now()) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  ret RECORD;
BEGIN
  UPDATE queue_tasks
  SET
    started_at = now,
    consumer_id = consumer_id_arg,
    retries_left = retries_left - 1,
    heartbeat_deadline = now + heartbeat_timeout_arg,
    heartbeat_timeout = heartbeat_timeout_arg
  WHERE id IN (
    SELECT id FROM queue_tasks AS task
    WHERE topic = topic_arg AND priority >= min_priority AND queue_task_is_waiting_for_consume(task, now)
    ORDER BY priority DESC, added_at ASC
    LIMIT 1
    FOR UPDATE)
  RETURNING queue_tasks.id AS id, queue_tasks.data AS data, queue_tasks.retries_left AS retries_left
  INTO ret;
  RETURN ret;
END;
$$;


--
-- Name: queue_heartbeat_task(bigint, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_heartbeat_task(task_id bigint, consumer_id_arg text, now timestamp with time zone DEFAULT now()) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  ret RECORD;
BEGIN
  UPDATE queue_tasks
  SET heartbeat_deadline = now + heartbeat_timeout
  WHERE id = task_id AND consumer_id = consumer_id_arg AND NOT queue_task_is_canceled(queue_tasks, now)
  RETURNING queue_tasks.id
  INTO ret;
  RETURN ret;
END;
$$;


--
-- Name: queue_soft_drop_task(bigint, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_soft_drop_task(task_id bigint, consumer_id_arg text, now timestamp with time zone DEFAULT now()) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  ret RECORD;
BEGIN
  UPDATE queue_tasks
  SET heartbeat_deadline = now - INTERVAL '1 second'
  WHERE id = task_id AND consumer_id = consumer_id_arg
  RETURNING queue_tasks.id
  INTO ret;
  RETURN ret;
END;
$$;


--
-- Name: queue_task_is_canceled(public.queue_tasks, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_is_canceled(task public.queue_tasks, now timestamp with time zone DEFAULT now()) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN task.canceled_at IS NOT NULL OR
    (now > task.heartbeat_deadline AND task.retries_left = 0);
END;
$$;


--
-- Name: queue_task_is_committed(public.queue_tasks); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_is_committed(task public.queue_tasks) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN task.committed_at IS NOT NULL;
END;
$$;


--
-- Name: queue_task_is_started(public.queue_tasks, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_is_started(task public.queue_tasks, now timestamp with time zone DEFAULT now()) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN task.started_at IS NOT NULL AND
    task.committed_at IS NULL AND
    task.canceled_at IS NULL AND
    now <= task.heartbeat_deadline;
END;
$$;


--
-- Name: queue_task_is_waiting_for_consume(public.queue_tasks, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_is_waiting_for_consume(task public.queue_tasks, now timestamp with time zone DEFAULT now()) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (task.started_at IS NULL OR now > task.heartbeat_deadline) AND
    task.canceled_at IS NULL AND
    task.retries_left > 0;
END;
$$;
