pragma solidity ^0.8.23;

contract BovineTracking {
    struct Bovine {
        uint id;
        string name;
        uint age;
        string breed;
        string location;
        Vaccine[] vaccines;
        Movement[] movements;
        Feed[] feeds;
        HealthExam[] healthExams;
        AbattoirProcess[] abattoirProcesses;
    }

    struct Vaccine {
        string name;
        uint date;
    }

    struct Movement {
        string fromLocation;
        string toLocation;
        uint date;
    }

    struct Feed {
        string foodType;
        string origin;
        uint quantity;
        uint date;
    }

    struct HealthExam {
        string examType;
        string result;
        uint date;
    }

    struct AbattoirProcess {
        string abattoir;
        uint abattoirDate;
        string processing;
        uint date;
    }

    mapping(uint => Bovine) public bovinesById;
    mapping(string => uint) public bovineIdByName;
    mapping(uint => uint[]) public bovineVaccineDates;
    mapping(uint => uint[]) public bovineMovementDates;
    mapping(uint => uint[]) public bovineFeedDates;
    mapping(uint => uint[]) public bovineHealthExamDates;
    mapping(uint => uint[]) public bovineAbattoirProcessDates;
    mapping(string => uint[]) public bovineIdsByBreed;
    mapping(string => uint[]) public bovineIdsByLocation;

    uint public totalBovines;
    uint[] private bovineIds;

    function addBovine(
        string memory _name,
        uint _age,
        string memory _breed,
        string memory _location
    ) public {
        totalBovines++;

        Bovine storage newBovine = bovinesById[totalBovines];
        newBovine.id = totalBovines;
        newBovine.name = _name;
        newBovine.age = _age;
        newBovine.breed = _breed;
        newBovine.location = _location;

        bovineIdByName[_name] = totalBovines;
        bovineIds.push(totalBovines);
        bovineIdsByBreed[_breed].push(totalBovines);
        bovineIdsByLocation[_location].push(totalBovines);
    }

    function addVaccine(
        uint _bovineId,
        string memory _name,
        uint _date
    ) public {
        require(bovinesById[_bovineId].id != 0, "Invalid bovine ID");

        Vaccine memory newVaccine = Vaccine(_name, _date);
        bovinesById[_bovineId].vaccines.push(newVaccine);
        bovineVaccineDates[_bovineId].push(_date);
    }

    function addMovement(
        uint _bovineId,
        string memory _fromLocation,
        string memory _toLocation,
        uint _date
    ) public {
        require(bovinesById[_bovineId].id != 0, "Invalid bovine ID");

        Movement memory newMovement = Movement(
            _fromLocation,
            _toLocation,
            _date
        );

        bovinesById[_bovineId].movements.push(newMovement);
        bovineMovementDates[_bovineId].push(_date);
    }

    function addFeed(
        uint _bovineId,
        string memory _foodType,
        string memory _origin,
        uint _quantity,
        uint _date
    ) public {
        require(bovinesById[_bovineId].id != 0, "Invalid bovine ID");

        Feed memory newFeed = Feed(_foodType, _origin, _quantity, _date);
        bovinesById[_bovineId].feeds.push(newFeed);
        bovineFeedDates[_bovineId].push(_date);
    }

    function addHealthExam(
        uint _bovineId,
        string memory _examType,
        string memory _result,
        uint _date
    ) public {
        require(bovinesById[_bovineId].id != 0, "Invalid bovine ID");

        HealthExam memory newHealthExam = HealthExam(_examType, _result, _date);
        bovinesById[_bovineId].healthExams.push(newHealthExam);
        bovineHealthExamDates[_bovineId].push(_date);
    }

    function addAbattoirProcess(
        uint _bovineId,
        string memory _abattoir,
        uint _abattoirDate,
        string memory _processing,
        uint _date
    ) public {
        require(bovinesById[_bovineId].id != 0, "Invalid bovine ID");

        AbattoirProcess memory newAbattoirProcess = AbattoirProcess(
            _abattoir,
            _abattoirDate,
            _processing,
            _date
        );

        bovinesById[_bovineId].abattoirProcesses.push(newAbattoirProcess);
        bovineAbattoirProcessDates[_bovineId].push(_date);
    }

    function getBovineById(
        uint _bovineId
    )
        public
        view
        returns (
            uint,
            string memory,
            uint,
            string memory,
            string memory,
            Vaccine[] memory
        )
    {
        Bovine memory bovine = bovinesById[_bovineId];
        require(bovine.id != 0, "Invalid bovine ID");

        return (
            bovine.id,
            bovine.name,
            bovine.age,
            bovine.breed,
            bovine.location,
            bovine.vaccines
        );
    }

    function getBovineByName(
        string memory _name
    )
        public
        view
        returns (
            uint,
            string memory,
            uint,
            string memory,
            string memory,
            Vaccine[] memory
        )
    {
        uint bovineId = bovineIdByName[_name];
        require(bovineId != 0, "Invalid bovine name");

        return getBovineById(bovineId);
    }

    function getBovinesByDate(uint _date) public view returns (uint[] memory) {
        uint[] memory matchingBovineIds = new uint[](bovineIds.length);
        uint count = 0;

        for (uint i = 0; i < bovineIds.length; i++) {
            uint bovineId = bovineIds[i];
            if (
                arrayContains(bovineVaccineDates[bovineId], _date) ||
                arrayContains(bovineMovementDates[bovineId], _date) ||
                arrayContains(bovineFeedDates[bovineId], _date) ||
                arrayContains(bovineHealthExamDates[bovineId], _date) ||
                arrayContains(bovineAbattoirProcessDates[bovineId], _date)
            ) {
                matchingBovineIds[count] = bovineId;
                count++;
            }
        }

        assembly {
            mstore(matchingBovineIds, count)
        }

        return matchingBovineIds;
    }

    function arrayContains(
        uint[] memory arr,
        uint value
    ) internal pure returns (bool) {
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return true;
            }
        }

        return false;
    }

    function getBovinesByBreed(
        string memory _breed
    ) public view returns (uint[] memory) {
        return bovineIdsByBreed[_breed];
    }

    function getBovinesByLocation(
        string memory _location
    ) public view returns (uint[] memory) {
        return bovineIdsByLocation[_location];
    }

    function getTotalBovineCount() public view returns (uint) {
        return totalBovines;
    }

    function getVaccines(
        uint _bovineId
    ) public view returns (Vaccine[] memory) {
        return bovinesById[_bovineId].vaccines;
    }

    function getBovine(uint id) public view returns (Bovine memory) {
        return bovinesById[id];
    }
}
