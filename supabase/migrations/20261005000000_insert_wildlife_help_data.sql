-- Insert verified rescue contacts
INSERT INTO verified_rescue_contacts (name, organization, contact_type, district, state, phone, email, website, availability, status) VALUES
('Wildlife Crime Control Bureau', 'Central Govt', 'control_room', 'All', 'All India', '1800-11-9334', 'wccb@nic.in', 'wccb.gov.in', '24x7', 'verified'),
('Wildlife Rescue Centre', 'West Bengal Forest Dept', 'rescue_centre', 'Kolkata', 'West Bengal', '033-2334-6900', NULL, 'westbengalforest.gov.in', 'Daytime', 'verified'),
('Aranya Bhawan HQ', 'West Bengal Forest Dept', 'headquarters', 'Kolkata', 'West Bengal', '033-2335-8581', 'pccfhoff.fd-wb@gov.in', 'westbengalforest.gov.in', 'Office Hours', 'verified'),
('Sundarban Tiger Reserve', 'West Bengal Forest Dept', 'reserve_office', 'South 24 Parganas', 'West Bengal', '03210-255070', 'strfd.fd-wb@gov.in', 'sundarbantigerreserve.org', '24x7', 'verified')
ON CONFLICT DO NOTHING;

-- Insert safety guidelines
INSERT INTO wildlife_safety_guidelines (title, content, display_order, is_published) VALUES
('সাপ দেখলে কী করবেন?', 'সাপ দেখলে ভয় পাবেন না বা তাকে মারার চেষ্টা করবেন না। সাপ থেকে অন্তত ১০ ফুট দূরত্ব বজায় রাখুন। সাপ সাধারণত নিজ থেকে আক্রমণ করে না। বনদপ্তর বা নিকটবর্তী বন্যপ্রাণী উদ্ধারকারী দলে খবর দিন।', 1, true),
('বন্যপ্রাণী লোকালয়ে প্রবেশ করলে', 'বন্যপ্রাণীকে উত্যক্ত করবেন না। ভিড় জমাবেন না, এতে প্রাণীটি ভয় পেয়ে আক্রমণ করতে পারে। প্রাণীটির যাওয়ার জন্য একটি নিরাপদ রাস্তা খোলা রাখুন এবং দ্রুত বনদপ্তরে জানান।', 2, true),
('আহত পাখি বা পশু দেখলে', 'আহত প্রাণীকে নিজে চিকিৎসা করার চেষ্টা করবেন না। তাকে একটি সুরক্ষিত জায়গায় রাখুন (যেমন কার্টবোর্ড বক্স)। জল বা খাবার জোর করে খাওয়াবেন না। দ্রুত বিশেষজ্ঞদের সাথে যোগাযোগ করুন।', 3, true)
ON CONFLICT DO NOTHING;
