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