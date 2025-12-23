import pendulum

class Preprocessing:
    """
        Utils for preprocessing dataset
    """

    def __init__(self):
        pass


    def split_time_context(self, execution_date):
        """
            Split execution_date (datetime)
            into 
                ymd : YYYY-MM-DD 
                hm  : HHMM (HourMinute)
        """

        kst = pendulum.timezone("Asia/Seoul")
        execution_date_kst = execution_date.in_timezone(kst)

        ymd = execution_date_kst.strftime("%Y-%m-%d")
        hm = execution_date_kst.strftime("%H%M")
        return ymd, hm
    
    def split_ymd(self, ymd):
        """
            Split year-month-day to YearMonthDay
            param
                ymd : year-month-day
        """
        return ymd.replace('-', '')
    

    def match_coordinates(self, df, address1, address2):
        """
            From database, extract nx and ny matched with address1 and address2
            param
                df : DataFrame of coordinate meta data
                address1 : State
                address2 : City
        """
        target = df[(df['1단계'] == address1) & (df['2단계'] == address2)]
        return target[['격자 X', '격자 Y']].iloc[0]