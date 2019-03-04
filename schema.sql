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
-- Name: queue_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.queue_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: queue_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queue_tasks (
    id bigint DEFAULT nextval('public.queue_tasks_id_seq'::regclass) NOT NULL,
    topic text NOT NULL,
    priority bigint NOT NULL,
    consumer_id text,
    retries_left bigint NOT NULL,
    heartbeat_deadline timestamp with time zone,
    added_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone,
    committed_at timestamp with time zone,
    canceled_at timestamp with time zone,
    data bytea NOT NULL,
    heartbeat_timeout interval
);

ALTER TABLE ONLY public.queue_tasks
    ADD CONSTRAINT queue_tasks_pkey PRIMARY KEY (id);

CREATE INDEX idx_tasks_topic_state ON public.queue_tasks USING btree (topic, priority DESC, started_at, canceled_at, heartbeat_deadline, retries_left);
