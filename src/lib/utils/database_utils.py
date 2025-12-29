import psycopg2
import os

class Database_utils:
    """
        Connect to PostgresDB to inspect and get data
    """

    def __init__(self):
        conn = psycopg2.connect(
            host = os.getenv('APP_DB_HOST'),
            database = os.getenv('APP_DB_NAME'),
            user = os.getenv('APP_DB_USER'),
            password = os.getenv('APP_DB_PSWD')
        )

        self.cur = conn.cursor()



    def get_unique_address(self):
        """
            Get all unique address of home and work
        """
        self.cur.execute("""
            select home_address, work_address from "user".user_info
        """)
        rows = self.cur.fetchall()

        merge = list({item for row in rows for item in row})
        return merge