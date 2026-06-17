-- Issue 0 seed. Run in the Supabase SQL editor (runs as owner, bypasses RLS).
--
-- IMPORTANT: the app reads with the anon key, so issues / pages / page_media
-- each need a SELECT RLS policy (or RLS disabled) or the magazine loads empty.

-- 1. Schema: page_media doubles as the universal widget row.
alter table page_media add column if not exists text_content text;
alter table page_media alter column media_url drop not null;  -- text widgets have no URL

-- 2. Issue 0 + 3 pages + widgets. Explicit created_at keeps page order stable
--    (cover first), since fetchCurrentIssue orders pages by created_at.
do $$
declare
  v_issue uuid;
  v_cover uuid;
  v_page1 uuid;
  v_page2 uuid;
begin
  insert into issues (publish_date, is_live)
    values ('2026-06-17', true) returning id into v_issue;

  insert into pages (issue_id, created_at)
    values (v_issue, now())                       returning id into v_cover;
  insert into pages (issue_id, created_at)
    values (v_issue, now() + interval '1 second')  returning id into v_page1;
  insert into pages (issue_id, created_at)
    values (v_issue, now() + interval '2 seconds') returning id into v_page2;

  -- Cover: a single full-bleed image (the NASA cover you chose).
  insert into page_media (page_id, media_type, media_url, position) values
    (v_cover, 'image',
     'https://images-assets.nasa.gov/image/art002e009571/art002e009571~large.jpg?w=1920&h=1440&fit=clip&crop=faces%2Cfocalpoint',
     0);

  -- Page 1: text + two images + audio.
  insert into page_media (page_id, media_type, media_url, text_content, position) values
    (v_page1, 'text',  null, 'Welcome to Circle — Issue 0.', 0),
    (v_page1, 'image', 'https://picsum.photos/seed/circle1/1200/1200', null, 1),
    (v_page1, 'image', 'https://picsum.photos/seed/circle2/1200/1200', null, 2),
    (v_page1, 'audio', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', null, 3);

  -- Page 2: video + text + image.
  insert into page_media (page_id, media_type, media_url, text_content, position) values
    (v_page2, 'video', 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4', null, 0),
    (v_page2, 'text',  null, 'Tap any widget to zoom it fullscreen.', 1),
    (v_page2, 'image', 'https://picsum.photos/seed/circle3/1200/1200', null, 2);
end $$;
