-- Create enum types
CREATE TYPE user_role AS ENUM ('student', 'faculty', 'guest');
CREATE TYPE room_type AS ENUM ('ac', 'non_ac');
CREATE TYPE booking_status AS ENUM ('pending', 'approved', 'rejected', 'paid', 'confirmed', 'cancelled');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed');
CREATE TYPE app_role AS ENUM ('admin', 'user');

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role user_role NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  student_id TEXT,
  faculty_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Create user_roles table for admin management
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL DEFAULT 'user',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer function to check roles
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE POLICY "Admins can view all user roles"
  ON public.user_roles FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

-- Create guest_houses table
CREATE TABLE public.guest_houses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  is_female_only BOOLEAN DEFAULT FALSE,
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.guest_houses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view guest houses"
  ON public.guest_houses FOR SELECT
  USING (true);

CREATE POLICY "Only admins can modify guest houses"
  ON public.guest_houses FOR ALL
  USING (public.has_role(auth.uid(), 'admin'));

-- Create rooms table
CREATE TABLE public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_house_id UUID REFERENCES public.guest_houses(id) ON DELETE CASCADE NOT NULL,
  room_number TEXT NOT NULL,
  type room_type NOT NULL,
  price_per_person DECIMAL(10, 2) NOT NULL,
  max_occupancy INTEGER DEFAULT 2,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view rooms"
  ON public.rooms FOR SELECT
  USING (true);

CREATE POLICY "Only admins can modify rooms"
  ON public.rooms FOR ALL
  USING (public.has_role(auth.uid(), 'admin'));

-- Create bookings table
CREATE TABLE public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  guest_house_id UUID REFERENCES public.guest_houses(id) NOT NULL,
  room_id UUID REFERENCES public.rooms(id) NOT NULL,
  check_in_date DATE NOT NULL,
  check_out_date DATE NOT NULL,
  number_of_guests INTEGER NOT NULL CHECK (number_of_guests <= 2),
  total_amount DECIMAL(10, 2) NOT NULL,
  status booking_status DEFAULT 'pending',
  payment_status payment_status DEFAULT 'pending',
  admin_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own bookings"
  ON public.bookings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own bookings"
  ON public.bookings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own pending bookings"
  ON public.bookings FOR UPDATE
  USING (auth.uid() = user_id AND status = 'pending');

CREATE POLICY "Admins can view all bookings"
  ON public.bookings FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update all bookings"
  ON public.bookings FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'));

-- Create booking_members table
CREATE TABLE public.booking_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID REFERENCES public.bookings(id) ON DELETE CASCADE NOT NULL,
  full_name TEXT NOT NULL,
  id_proof_url TEXT,
  id_proof_type TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.booking_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view members of their own bookings"
  ON public.booking_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.bookings
      WHERE bookings.id = booking_members.booking_id
      AND bookings.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert members for their own bookings"
  ON public.booking_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.bookings
      WHERE bookings.id = booking_members.booking_id
      AND bookings.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can view all booking members"
  ON public.booking_members FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_bookings_updated_at
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create storage buckets
INSERT INTO storage.buckets (id, name, public)
VALUES ('id-proofs', 'id-proofs', false);

-- Create storage policies for ID proofs
CREATE POLICY "Users can upload their own ID proofs"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'id-proofs' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can view their own ID proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'id-proofs'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Admins can view all ID proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'id-proofs'
    AND public.has_role(auth.uid(), 'admin')
  );

-- Insert initial guest houses data
INSERT INTO public.guest_houses (name, description, is_female_only) VALUES
('Anandi Bai Joshi Guest House', 'Exclusively for female guests with comfortable accommodations', true),
('Main Guest House', 'Premium guest house with modern amenities', false),
('Ramanujan Guest House', 'Standard guest house with essential facilities', false);

-- Insert rooms for each guest house
-- Anandi Bai Joshi rooms
INSERT INTO public.rooms (guest_house_id, room_number, type, price_per_person)
SELECT id, 'ABJ-' || generate_series || '-' || CASE WHEN generate_series % 2 = 0 THEN 'AC' ELSE 'NAC' END,
       CASE WHEN generate_series % 2 = 0 THEN 'ac'::room_type ELSE 'non_ac'::room_type END,
       CASE WHEN generate_series % 2 = 0 THEN 600 ELSE 400 END
FROM public.guest_houses, generate_series(1, 10)
WHERE name = 'Anandi Bai Joshi Guest House';

-- Main Guest House rooms
INSERT INTO public.rooms (guest_house_id, room_number, type, price_per_person)
SELECT id, 'MGH-' || generate_series || '-' || CASE WHEN generate_series % 2 = 0 THEN 'AC' ELSE 'NAC' END,
       CASE WHEN generate_series % 2 = 0 THEN 'ac'::room_type ELSE 'non_ac'::room_type END,
       CASE WHEN generate_series % 2 = 0 THEN 1600 ELSE 1200 END
FROM public.guest_houses, generate_series(1, 10)
WHERE name = 'Main Guest House';

-- Ramanujan Guest House rooms
INSERT INTO public.rooms (guest_house_id, room_number, type, price_per_person)
SELECT id, 'RGH-' || generate_series || '-' || CASE WHEN generate_series % 2 = 0 THEN 'AC' ELSE 'NAC' END,
       CASE WHEN generate_series % 2 = 0 THEN 'ac'::room_type ELSE 'non_ac'::room_type END,
       CASE WHEN generate_series % 2 = 0 THEN 600 ELSE 400 END
FROM public.guest_houses, generate_series(1, 10)
WHERE name = 'Ramanujan Guest House';

-- Insert admin users with predefined credentials
-- Note: Actual password hashing will be handled by Supabase Auth
-- These are placeholders for the admin role assignments
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin'::app_role
FROM auth.users
WHERE email IN (
  'rishibalai007@gmail.com',
  'siddhidavane2007@gmail.com',
  'kevaldesai@gmail.com',
  'pallavidas@gmail.com'
);

-- Function to check room availability
CREATE OR REPLACE FUNCTION public.check_room_availability(
  p_room_id UUID,
  p_check_in DATE,
  p_check_out DATE
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE room_id = p_room_id
    AND status NOT IN ('rejected', 'cancelled')
    AND (
      (check_in_date <= p_check_in AND check_out_date > p_check_in)
      OR (check_in_date < p_check_out AND check_out_date >= p_check_out)
      OR (check_in_date >= p_check_in AND check_out_date <= p_check_out)
    )
  );
$$;