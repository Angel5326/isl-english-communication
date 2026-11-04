import psycopg2

# 1. Paste your External Database URL here (inside the quotes)
DATABASE_URL = "postgresql://handytalk_db_user:ImHfFdB23f3L4LWFHF9wZhLBgLXd7iTw@dpg-dbl9ngrncjis73d73hv0-a.singapore-postgres.render.com/handytalk_db"

# 2. Type the email address you are trying to register with
EMAIL_TO_DELETE = "abiangelin814@gmail.com" 

try:
    print("Connecting to database...")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True # Required for table creation
    cur = conn.cursor()
    
    # 1. Create the table if it doesn't exist
    print("Checking if 'users' table exists...")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            name VARCHAR,
            email VARCHAR UNIQUE,
            hashed_password VARCHAR,
            is_verified BOOLEAN DEFAULT FALSE,
            otp VARCHAR
        );
    """)
    
    # 2. Try to delete the user
    print("Checking for unverified user...")
    cur.execute("DELETE FROM users WHERE email = %s;", (EMAIL_TO_DELETE,))
    
    print(f"✅ Success! The table exists and any unverified user with {EMAIL_TO_DELETE} has been removed.")
    
    cur.close()
    conn.close()
except Exception as e:
    print(f"❌ Error: {e}")