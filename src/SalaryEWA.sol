// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SalaryEWA is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PAY_PERIOD = 30 days;
    IERC20 public immutable SALARY_TOKEN;

    struct Employee {
        uint256 monthlySalary;
        uint256 employmentStart;
        uint256 lastUpdate;
        uint256 accrued;
        uint256 withdrawn;
        uint256 refunded;
        uint256 lastAdvancePeriod;
        bool active;
        bool exists;
    }

    mapping(address => Employee) private employees;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event EmployeeRegistered(address indexed employee, uint256 salary);
    event EmployeeUpdated(address indexed employee, uint256 oldSalary, uint256 newSalary);
    event EmployeeDeactivated(address indexed employee);
    event EmployeeReactivated(address indexed employee);
    event Funded(address indexed from, uint256 amount);
    event AdvanceRequested(address indexed employee, uint256 amount, uint256 periodIndex);
    event Withdrawn(address indexed employee, uint256 amount);
    event SalaryReleased(address indexed employee, uint256 amount);
    event EmployeeRefunded(address indexed employee, uint256 amount);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyEmployer() {
        _onlyEmployer();
        _;
    }

    modifier onlyEmployee() {
        _onlyEmployee();
        _;
    }

    modifier onlyActiveEmployee() {
        _onlyActiveEmployee();
        _;
    }

    function _onlyEmployer() internal view {
        require(owner() == _msgSender(), "Not employer");
    }

    function _onlyEmployee() internal view {
        require(employees[msg.sender].exists, "Not employee");
    }

    function _onlyActiveEmployee() internal view {
        Employee storage emp = employees[msg.sender];
        require(emp.exists, "Not employee");
        require(emp.active, "Inactive");
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(IERC20 _salaryToken) {
        require(address(_salaryToken) != address(0), "Invalid token");
        SALARY_TOKEN = _salaryToken;
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function _currentPeriodIndex(Employee storage emp) internal view returns (uint256) {
        if (emp.employmentStart == 0) return 0;
        return (block.timestamp - emp.employmentStart) / PAY_PERIOD;
    }

    function _updateAccrual(Employee storage emp) internal {
        if (!emp.exists) return;

        uint256 elapsed = block.timestamp - emp.lastUpdate;
        if (elapsed == 0) return;

        uint256 earned = (emp.monthlySalary * elapsed) / PAY_PERIOD;
        emp.accrued += earned;
        emp.lastUpdate = block.timestamp;
    }

    function _withdrawable(Employee storage emp) internal view returns (uint256) {
        if (!emp.exists) return 0;
        uint256 used = emp.withdrawn + emp.refunded;
        return emp.accrued > used ? emp.accrued - used : 0;
    }

    // -----------------------------------------------------------------------
    // Employer Functions
    // -----------------------------------------------------------------------

    function registerEmployee(address _employee, uint256 _monthlySalary) external onlyEmployer whenNotPaused {
        require(_employee != address(0), "Zero address");
        require(_monthlySalary > 0, "Salary > 0");

        Employee storage emp = employees[_employee];
        require(!emp.exists, "Already exists");

        emp.monthlySalary = _monthlySalary;
        emp.employmentStart = block.timestamp;
        emp.lastUpdate = block.timestamp;
        emp.active = true;
        emp.exists = true;

        emit EmployeeRegistered(_employee, _monthlySalary);
    }

    function updateEmployeeSalary(address _employee, uint256 _newMonthlySalary) external onlyEmployer whenNotPaused {
        require(_newMonthlySalary > 0, "Salary > 0");

        Employee storage emp = employees[_employee];
        require(emp.exists, "Not employee");

        _updateAccrual(emp);

        uint256 oldSalary = emp.monthlySalary;
        emp.monthlySalary = _newMonthlySalary;

        emit EmployeeUpdated(_employee, oldSalary, _newMonthlySalary);
    }

    function deactivateEmployee(address _employee) external onlyEmployer {
        Employee storage emp = employees[_employee];
        require(emp.exists, "Not employee");
        require(emp.active, "Already inactive");

        emp.active = false;
        emit EmployeeDeactivated(_employee);
    }

    function reactivateEmployee(address _employee) external onlyEmployer {
        Employee storage emp = employees[_employee];
        require(emp.exists, "Not employee");
        require(!emp.active, "Already active");

        emp.active = true;
        emp.lastUpdate = block.timestamp;

        emit EmployeeReactivated(_employee);
    }

    function fund(uint256 _amount) external onlyEmployer nonReentrant whenNotPaused {
        require(_amount > 0, "Amount > 0");
        SALARY_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        emit Funded(msg.sender, _amount);
    }

    function releaseSalary(address _employee) external onlyEmployer nonReentrant whenNotPaused {
        Employee storage emp = employees[_employee];
        require(emp.exists, "Not employee");

        _updateAccrual(emp);

        uint256 amount = _withdrawable(emp);
        require(amount > 0, "No salary");

        emp.withdrawn += amount;

        SALARY_TOKEN.safeTransfer(_employee, amount);
        emit SalaryReleased(_employee, amount);
    }

    function refundEmployee(address _employee, uint256 _amount) external onlyEmployer nonReentrant whenNotPaused {
        Employee storage emp = employees[_employee];
        require(emp.exists, "Not employee");

        _updateAccrual(emp);

        uint256 withdrawableAmount = _withdrawable(emp);
        require(_amount <= withdrawableAmount, "Exceeds refundable");

        emp.refunded += _amount;

        SALARY_TOKEN.safeTransfer(owner(), _amount);
        emit EmployeeRefunded(_employee, _amount);
    }

    // -----------------------------------------------------------------------
    // Employee Functions
    // -----------------------------------------------------------------------

    function requestAdvance(uint256 _amount) external onlyActiveEmployee nonReentrant whenNotPaused {
        Employee storage emp = employees[msg.sender];
        _updateAccrual(emp);

        uint256 periodIndex = _currentPeriodIndex(emp);
        require(emp.lastAdvancePeriod < periodIndex, "Already advanced");

        uint256 withdrawableAmount = _withdrawable(emp);
        require(withdrawableAmount > 0, "Nothing earned");

        uint256 maxAdvance = withdrawableAmount / 2;
        require(_amount <= maxAdvance, "Exceeds 50%");

        emp.withdrawn += _amount;
        emp.lastAdvancePeriod = periodIndex;

        SALARY_TOKEN.safeTransfer(msg.sender, _amount);

        emit AdvanceRequested(msg.sender, _amount, periodIndex);
    }

    function withdraw() external onlyEmployee nonReentrant whenNotPaused {
        Employee storage emp = employees[msg.sender];
        _updateAccrual(emp);

        uint256 amount = _withdrawable(emp);
        require(amount > 0, "Nothing");

        emp.withdrawn += amount;
        SALARY_TOKEN.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // View Functions
    // -----------------------------------------------------------------------

    function isEmployee(address _employee) external view returns (bool) {
        return employees[_employee].exists;
    }

    function isActiveEmployee(address _employee) external view returns (bool) {
        return employees[_employee].exists && employees[_employee].active;
    }

    function previewWithdrawable(address _employee) external view returns (uint256) {
        Employee storage emp = employees[_employee];
        if (!emp.exists) return 0;

        uint256 tmp = emp.accrued;
        if (emp.lastUpdate > 0) {
            uint256 elapsed = block.timestamp - emp.lastUpdate;
            tmp += (emp.monthlySalary * elapsed) / PAY_PERIOD;
        }

        uint256 used = emp.withdrawn + emp.refunded;
        return tmp <= used ? 0 : tmp - used;
    }
}
