-- Create Tables

--VENUE
CREATE TABLE Venue (
    VenueID SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Capacity INT NOT NULL,
    Address TEXT NOT NULL
);

--SECTION
CREATE TABLE Section (
    SectionID SERIAL PRIMARY KEY,
    VenueID INT NOT NULL, 
    Name VARCHAR(100) NOT NULL,
    SeatCount INT NOT NULL,
    SectionType CHAR(1) NOT NULL CHECK (SectionType IN ('V', 'R')),
    FOREIGN KEY (VenueID) REFERENCES Venue(VenueID) 
        ON DELETE CASCADE ON UPDATE CASCADE
);

--VIP
CREATE TABLE Vip (
    SectionID INT PRIMARY KEY,
    VipExtras VARCHAR(100),
    FOREIGN KEY (SectionID) REFERENCES Section(SectionID) 
        ON DELETE CASCADE ON UPDATE CASCADE
);

--REGULAR
CREATE TABLE Regular (
    SectionID INT PRIMARY KEY,
    RegularExtras VARCHAR(100),
    FOREIGN KEY (SectionID) REFERENCES Section(SectionID)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX section_disjoint ON Section (SectionID, SectionType);
CREATE INDEX idx_section_venue ON Section (VenueID);
CREATE INDEX idx_vip_sectionid ON Vip (SectionID);
CREATE INDEX idx_regular_sectionid ON Regular (SectionID);

--CATEGORY
CREATE TABLE Category (
    CategoryID SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Description TEXT
);

--MEMBER
CREATE TABLE Member (
    UserID SERIAL PRIMARY KEY,
    Username VARCHAR(100) UNIQUE NOT NULL,
    Name VARCHAR(100) NOT NULL,
    Email VARCHAR(150) UNIQUE NOT NULL,
    PhoneNumber VARCHAR(11) UNIQUE NOT NULL,
    DateOfBirth DATE NOT NULL
);

--EVENT
CREATE TABLE Event (
    EventID SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    Date DATE NOT NULL,
    Location VARCHAR(150),
    AgeRestriction INT,
    CategoryID INT, 
    VenueID INT, 
    FOREIGN KEY (CategoryID) REFERENCES Category(CategoryID),
    FOREIGN KEY (VenueID) REFERENCES Venue(VenueID)
);

--RECEIPT
CREATE TABLE Receipt (
    ReceiptID SERIAL PRIMARY KEY,
    Amount DECIMAL(10, 2),
    ReceiptDate DATE,
    UserID INT,
    FOREIGN KEY (UserID) REFERENCES Member(UserID) ON DELETE CASCADE ON UPDATE CASCADE
);

--TICKET
CREATE TABLE Ticket (
    TicketID SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Category VARCHAR(50),
    SeatNumber VARCHAR(20),
    Price DECIMAL(10, 2),
    DateOfPurchase DATE NOT NULL,
    PurchaseStatus VARCHAR(50) NOT NULL,
    EventID INT, 
    ReceiptID INT, 
    SectionID INT,   
    UserID INT NOT NULL, 
    FOREIGN KEY (EventID) REFERENCES Event(EventID),
    FOREIGN KEY (ReceiptID) REFERENCES Receipt(ReceiptID),
    FOREIGN KEY (SectionID) REFERENCES Section(SectionID),
    FOREIGN KEY (UserID) REFERENCES Member(UserID) ON DELETE CASCADE ON UPDATE CASCADE
);

--PURCHASELOG
CREATE TABLE PurchaseLog (
    LogID SERIAL PRIMARY KEY,
    UserID INT NOT NULL,
    PurchaseDate DATE NOT NULL,
    TicketID INT,
    FOREIGN KEY (TicketID) REFERENCES Ticket(TicketID),
    FOREIGN KEY (UserID) REFERENCES Member(UserID) ON DELETE CASCADE ON UPDATE CASCADE
);

--DISCOUNT
CREATE TABLE Discount (
    DiscountID SERIAL PRIMARY KEY,
    Code VARCHAR(50) UNIQUE NOT NULL,
    Percentage DECIMAL(5, 2),
    StartDate DATE,
    EndDate DATE
);

--DISCOUNTRECEIPT
CREATE TABLE DiscountReceipt (
    ReceiptDiscountNo SERIAL PRIMARY KEY, 
    DiscountID INT NOT NULL,            
    ReceiptID INT NOT NULL,              
    Amount DECIMAL(10, 2),
    ReceiptDate DATE,
    FOREIGN KEY (DiscountID) REFERENCES Discount(DiscountID),
    FOREIGN KEY (ReceiptID) REFERENCES Receipt(ReceiptID) ON DELETE CASCADE ON UPDATE CASCADE,
    UNIQUE (DiscountID, ReceiptID)   
);

-- Triggers and Functions

--Trigger for checking age restriction.
CREATE OR REPLACE FUNCTION enforce_age_restriction()
RETURNS TRIGGER AS $$
DECLARE
    event_age_restriction INT;
    user_age INT;
BEGIN
    SELECT AgeRestriction INTO event_age_restriction
    FROM Event
    WHERE EventID = NEW.EventID;
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, DateOfBirth)) INTO user_age
    FROM Member
    WHERE UserID = NEW.UserID;
    IF user_age < event_age_restriction THEN
        RAISE EXCEPTION 'User with ID % does not meet the age restriction (% years old required, but user is % years old) for event ID %',
            NEW.UserID, event_age_restriction, user_age, NEW.EventID;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_age_restriction
BEFORE INSERT ON Ticket
FOR EACH ROW
EXECUTE FUNCTION enforce_age_restriction();

--Trigger for updating purchase status
CREATE OR REPLACE FUNCTION update_purchase_status()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'NEW.Amount: %, NEW.ReceiptID: %', NEW.Amount, NEW.ReceiptID;
    IF (NEW.Amount > 0) THEN
        RAISE NOTICE 'Amount is positive, updating PurchaseStatus to Paid';
        UPDATE Ticket SET PurchaseStatus = 'Paid' WHERE ReceiptID = NEW.ReceiptID;
    ELSE
        RAISE NOTICE 'Amount is zero or negative, updating PurchaseStatus to Pending';
        UPDATE Ticket SET PurchaseStatus = 'Pending' WHERE ReceiptID = NEW.ReceiptID;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_update_status
AFTER INSERT OR UPDATE ON Receipt
FOR EACH ROW
EXECUTE FUNCTION update_purchase_status();

--Triger for preventing people from double booking.
CREATE OR REPLACE FUNCTION prevent_double_booking()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Ticket WHERE SeatNumber = NEW.SeatNumber AND EventID = NEW.EventID) THEN
        RAISE EXCEPTION 'This seat is already booked for the event';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_double_booking
BEFORE INSERT ON Ticket
FOR EACH ROW
EXECUTE FUNCTION prevent_double_booking();

--Trigger for automatically createing a log for a purchase.
CREATE OR REPLACE FUNCTION log_ticket_purchase()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO PurchaseLog (UserID, PurchaseDate)
    VALUES (NEW.UserID, NEW.DateOfPurchase);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trigger_log_purchase
AFTER INSERT ON Ticket
FOR EACH ROW
EXECUTE FUNCTION log_ticket_purchase();

--Trigger for automaticly applying discounts.
CREATE OR REPLACE FUNCTION apply_discount()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Discount WHERE DiscountID = NEW.DiscountID AND CURRENT_DATE BETWEEN StartDate AND EndDate) THEN
        UPDATE Receipt SET Amount = Amount - (Amount * (SELECT Percentage FROM Discount WHERE DiscountID = NEW.DiscountID) / 100) WHERE ReceiptID = NEW.ReceiptID;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_apply_discount
AFTER INSERT ON DiscountReceipt
FOR EACH ROW
EXECUTE FUNCTION apply_discount();


--Function for checking event capacity.
CREATE OR REPLACE FUNCTION check_event_capacity(event_id INT) RETURNS BOOLEAN AS $$
DECLARE
    total_seats INT;
    sold_tickets INT;
BEGIN
    total_seats := (SELECT SUM(SeatCount) FROM Section WHERE VenueID = (SELECT VenueID FROM Event WHERE EventID = event_id));
    sold_tickets := (SELECT COUNT(*) FROM Ticket WHERE EventID = event_id);
    RETURN (total_seats > sold_tickets);
END;
$$ LANGUAGE plpgsql;

--Function for checking the sold tickets
CREATE OR REPLACE FUNCTION list_ticket_sales(event_id INT) RETURNS TABLE (
    TicketID INT,
    Username VARCHAR,
    SeatNumber VARCHAR,
    Price DECIMAL(10, 2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT t.TicketID, m.Username, t.SeatNumber, t.Price
    FROM Ticket t
    JOIN Member m ON t.UserID = m.UserID
    WHERE t.EventID = event_id;
END;
$$ LANGUAGE plpgsql;

--Function for getting history of a user.
CREATE OR REPLACE FUNCTION get_user_history(user_id INT) RETURNS TABLE (
    EventName VARCHAR,
    PurchaseDate DATE,
    Price DECIMAL(10, 2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT e.Name, t.DateOfPurchase, t.Price
    FROM Ticket t
    JOIN Event e ON t.EventID = e.EventID
    WHERE t.UserID = user_id;
END;
$$ LANGUAGE plpgsql;

--Function for calculating revenue.
CREATE OR REPLACE FUNCTION calculate_event_revenue(event_id INT) RETURNS DECIMAL(10, 2) AS $$
DECLARE
    total_revenue DECIMAL(10, 2);
BEGIN
    SELECT COALESCE(SUM(Price), 0) INTO total_revenue
    FROM Ticket
    WHERE EventID = event_id;
    RETURN total_revenue;
END;
$$ LANGUAGE plpgsql;

--Function for checking seats.
CREATE OR REPLACE FUNCTION get_available_seats(event_id INT)
RETURNS TABLE (SeatNumber TEXT) AS $$
BEGIN
    RETURN QUERY
    WITH seat_series AS (
        SELECT 
            s.Name AS SectionName, 
            gs AS SeatNumber
        FROM Section s
        CROSS JOIN LATERAL generate_series(1, s.SeatCount) AS gs
        WHERE s.VenueID = (SELECT VenueID FROM Event WHERE EventID = event_id)
    )
    SELECT 
        ss.SectionName || '-' || LPAD(ss.SeatNumber::TEXT, 3, '0') AS SeatNumber
    FROM seat_series ss
    WHERE NOT EXISTS (
        SELECT 1
        FROM Ticket t
        WHERE t.EventID = event_id 
          AND t.SeatNumber = (ss.SectionName || '-' || LPAD(ss.SeatNumber::TEXT, 3, '0'))::TEXT
    );
END;
$$ LANGUAGE plpgsql;

--Insert into table
INSERT INTO Venue (Name, Capacity, Address) 
VALUES 
('İstanbul Arena', 3000, 'Istanbul, Turkey'),
('Ankara Concert Hall', 2000, 'Ankara, Turkey'),
('Izmir Expo Center', 3000, 'Izmir, Turkey'),
('Antalya Open Air Theater', 3000, 'Antalya, Turkey'),
('Bursa Cultural Center', 1200, 'Bursa, Turkey');

INSERT INTO Section (VenueID, Name, SeatCount, SectionType)
VALUES
(1, 'Regular Area 1', 1000, 'R'),
(1, 'Regular Area 2', 1000, 'R'),
(1, 'VIP Area 1', 500, 'V'),
(1, 'VIP Area 2', 500, 'V'),
(2, 'Regular Area 1', 1000, 'R'),
(2, 'Regular Area 2', 1000, 'R'),
(3, 'Regular Area 1', 1000, 'R'),
(3, 'Regular Area 2', 1000, 'R'),
(3, 'VIP Area 1', 500, 'V'),
(3, 'VIP Area 2', 500, 'V'),
(4, 'Regular Area 1', 1000, 'R'),
(4, 'Regular Area 2', 1000, 'R'),
(4, 'VIP Area 1', 500, 'V'),
(4, 'VIP Area 2', 500, 'V'),
(5, 'Regular Area 1', 600, 'R'),
(5, 'Regular Area 2', 600, 'R');

INSERT INTO Regular (SectionID, RegularExtras)
SELECT SectionID, 'Standart Procedure' 
FROM Section
WHERE SectionType = 'R';

INSERT INTO Vip (SectionID, VipExtras)
SELECT SectionID, 'VIP Area Extras'  
FROM Section
WHERE SectionType = 'V';

INSERT INTO Category (Name, Description)
VALUES 
('Music', 'All music-related events'),
('Theater', 'Live theater performances'),
('Comedy', 'Stand-up comedy shows'),
('Dance', 'Dance performances and competitions'),
('Exhibitions', 'Art exhibitions and cultural events');

INSERT INTO Member (Username, Name, Email, PhoneNumber, DateOfBirth) 
VALUES 
('emre35', 'Emre Yıldız', 'emre.yildiz@example.com', '5323456789', '1995-02-20'),
('burcu22', 'Burcu Demir', 'burcu.demir@example.com', '5334567890', '1990-03-15'),
('murat56', 'Murat Kaya', 'murat.kaya@example.com', '5345678901', '1988-07-30'),
('selma89', 'Selma Güler', 'selma.guler@example.com', '5356789012', '1992-01-25'),
('caner44', 'Caner Aslan', 'caner.aslan@example.com', '5367890123', '1996-10-10'),
('ali15', 'Ali Yılmaz', 'ali.yilmaz@example.com', '5376543210', '2008-05-10');

INSERT INTO Event (Name, Description, Date, Location, AgeRestriction, CategoryID, VenueID) 
VALUES 
('Rock Festival', 'An exciting rock music festival', '2024-05-15', 'İstanbul Arena, Istanbul', 18, 1, 1),
('Turkish Theater Play', 'A traditional Turkish play with live music', '2024-06-20', 'Ankara Concert Hall, Ankara', 12, 2, 2),
('Stand-Up Comedy Night', 'Laugh out loud with top comedians', '2024-07-10', 'Izmir Expo Center, Izmir', 16, 3, 3),
('Sufi Dance Performance', 'A spiritual and cultural dance performance', '2024-08-01', 'Antalya Open Air Theater, Antalya', 0, 4, 4),
('Modern Art Exhibition', 'A collection of modern Turkish art', '2024-09-25', 'Bursa Cultural Center, Bursa', 0, 5, 5);

INSERT INTO Receipt (Amount, ReceiptDate, UserID) 
VALUES 
(150.00, '2024-05-15', 1),
(100.00, '2024-06-20', 2),
(200.00, '2024-07-10', 3),
(120.00, '2024-08-01', 4),
(180.00, '2024-09-25', 5);

INSERT INTO Ticket (Name, Category, SeatNumber, Price, DateOfPurchase, PurchaseStatus, EventID, ReceiptID, SectionID, UserID)
VALUES 
('Rock Fest Ticket', 'Music', 'A-1', 150.00, '2024-05-15', 'Paid', 1, 1, 3, 1),
('Theater Play Ticket', 'Theater', 'A-1', 100.00, '2024-06-20', 'Paid', 2, 5, 2, 2),
('Comedy Show Ticket', 'Comedy', 'A-1', 200.00, '2024-07-10', 'Paid', 3, 3, 8, 3),
('Dance Show Ticket', 'Dance', 'B-1', 120.00, '2024-08-01', 'Paid', 4, 4, 14, 4),
('Exhibition Ticket', 'Exhibitions', 'A-1', 180.00, '2024-09-25', 'Paid', 5, 5, 16, 5);

INSERT INTO Discount (Code, Percentage, StartDate, EndDate) 
VALUES 
('DISCOUNT10', 10.00, '2024-06-01', '2024-06-30'),
('DISCOUNT15', 15.00, '2024-07-01', '2024-07-15'),
('DISCOUNT20', 20.00, '2024-08-01', '2024-08-10'),
('DISCOUNT25', 25.00, '2024-09-01', '2024-09-30'),
('DISCOUNT30', 30.00, '2024-10-01', '2024-10-31');

INSERT INTO DiscountReceipt (DiscountID, ReceiptID, Amount, ReceiptDate) 
VALUES 
(1, 1, 135.00, '2024-05-15'),
(2, 2, 85.00, '2024-06-20'),
(3, 3, 160.00, '2024-07-10'),
(4, 4, 90.00, '2024-08-01'),
(5, 5, 126.00, '2024-09-25');

--TRIGGER CHECKS

--Age Restriction Trigger Check
--INSERT INTO Ticket (Name, Category, SeatNumber, Price, DateOfPurchase, PurchaseStatus, EventID, ReceiptID, SectionID, UserID) 
--VALUES 
--('Rock Fest Ticket', 'Music', 'A-2', 150.00, '2024-05-15', 'Paid', 1, 1, 1, (SELECT UserID FROM Member WHERE Username = 'ali15'));


--Update Purchase Status Trigger Check
--INSERT INTO Receipt (Amount, ReceiptDate, UserID)
--VALUES 
--(50.0, CURRENT_DATE, 1),
--(0.0, CURRENT_DATE, 1),
--(-10.0, CURRENT_DATE, 1);
--INSERT INTO Ticket (Name, Category, SeatNumber, Price, DateOfPurchase, PurchaseStatus, EventID, ReceiptID, SectionID, UserID)
--VALUES 
--('Concert A', 'Music', 'A1', 100.0, CURRENT_DATE, 'Paid', 1, 6, 1, 1),
--('Concert B', 'Music', 'A2', 150.0, CURRENT_DATE, 'Pending', 2, 7, 1, 1),
--('Concert C', 'Music', 'B1', 200.0, CURRENT_DATE, 'Pending', 3, 8, 1, 1);
--UPDATE Receipt
--SET Amount = 0.0
--WHERE ReceiptID = 6;
--UPDATE Receipt
--SET Amount = 100.0
--WHERE ReceiptID = 7; 
--UPDATE Receipt
--SET Amount = 100
--WHERE ReceiptID = 8;   


--Prevent Double Booking Trigger Check
--INSERT INTO Ticket (Name, Category, SeatNumber, Price, DateOfPurchase, PurchaseStatus, EventID, ReceiptID, SectionID, UserID)
--VALUES 
--('Concert A', 'Music', 'A1', 100.0, CURRENT_DATE, 'Pending', 1, 1, 1, 1);


--Automatic Log Trigger Check
--In code


--Automatically Applying Discount Check
--INSERT INTO Discount (Code, Percentage, StartDate, EndDate)
--VALUES ('INDIRIM10', 10.0, '2024-12-01', '2024-12-31');
--INSERT INTO DiscountReceipt (DiscountID, ReceiptID, Amount, ReceiptDate)
--VALUES (6, 1, 10.0, CURRENT_DATE);


--FUNCTION CHECKS
--1
--SELECT check_event_capacity(1);
--2
--SELECT * FROM list_ticket_sales(1);
--3
--SELECT * FROM get_user_history(1);
--4
--SELECT calculate_event_revenue(1);
--5
--SELECT * FROM get_available_seats(1);








