// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Micro Insurance for Digital Nomads
 * @dev Location-based micro insurance with dynamic risk assessment and community pooling
 * @author Digital Nomad Insurance Protocol
 */
contract Project {
    
    // State variables
    address public owner;
    uint256 public totalInsurancePool;
    uint256 public totalPoliciesCreated;
    uint256 public totalClaimsPaid;
    
    // Constants
    uint256 public constant BASE_PREMIUM_RATE = 0.0005 ether; // Base rate per day
    uint256 public constant MIN_POLICY_DURATION = 1 days;
    uint256 public constant MAX_POLICY_DURATION = 180 days;
    uint256 public constant POOL_RESERVE_RATIO = 20; // 20% reserve requirement
    
    // Enums
    enum PolicyStatus { Active, Expired, Claimed, Cancelled }
    enum ClaimStatus { Pending, Approved, Rejected }
    
    // Structs
    struct InsurancePolicy {
        address nomad;
        string currentLocation;
        uint256 coverageAmount;
        uint256 premiumPaid;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 locationRiskScore;
        PolicyStatus status;
        bool hasActiveClaim;
    }
    
    struct LocationProfile {
        uint256 riskScore; // 1-1000 (1 = lowest risk, 1000 = highest risk)
        uint256 maxCoverageLimit;
        uint256 averageClaimAmount;
        bool isActiveLocation;
        string riskFactors; // JSON string of risk factors
    }
    
    struct ClaimRequest {
        address claimant;
        uint256 policyId;
        uint256 requestedAmount;
        string claimDescription;
        string evidenceHash; // IPFS hash for evidence
        uint256 submissionTime;
        ClaimStatus status;
    }
    
    // Mappings
    mapping(address => uint256[]) public nomadPolicies;
    mapping(uint256 => InsurancePolicy) public policies;
    mapping(string => LocationProfile) public locationProfiles;
    mapping(uint256 => ClaimRequest) public claims;
    mapping(address => uint256) public nomadReputation; // 0-100 score
    
    // Counters
    uint256 public nextPolicyId = 1;
    uint256 public nextClaimId = 1;
    
    // Events
    event PolicyCreated(
        uint256 indexed policyId, 
        address indexed nomad, 
        string location, 
        uint256 coverage, 
        uint256 premium
    );
    
    event LocationUpdated(
        uint256 indexed policyId, 
        address indexed nomad, 
        string oldLocation, 
        string newLocation,
        uint256 adjustedPremium
    );
    
    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed claimant,
        uint256 amount,
        string description
    );
    
    event ClaimProcessed(
        uint256 indexed claimId,
        bool approved,
        uint256 payoutAmount
    );
    
    event PoolContribution(address indexed contributor, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can execute this");
        _;
    }
    
    modifier validPolicy(uint256 _policyId) {
        require(_policyId > 0 && _policyId < nextPolicyId, "Invalid policy ID");
        require(policies[_policyId].nomad == msg.sender, "Not your policy");
        _;
    }
    
    modifier activePolicyOnly(uint256 _policyId) {
        require(policies[_policyId].status == PolicyStatus.Active, "Policy not active");
        require(block.timestamp <= policies[_policyId].endTimestamp, "Policy expired");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        
        // Initialize popular nomad destinations with risk profiles
        _initializeLocationProfiles();
    }
    
    /**
     * @dev Core Function 1: Create a micro insurance policy for digital nomads
     * @param _location Current location of the nomad
     * @param _durationDays Duration of coverage in days
     * @param _preferredCoverage Desired coverage amount
     */
    function createMicroPolicy(
        string memory _location,
        uint256 _durationDays,
        uint256 _preferredCoverage
    ) external payable returns (uint256 policyId) {
        
        require(_durationDays >= 1 && _durationDays <= 180, "Invalid duration");
        require(locationProfiles[_location].isActiveLocation, "Location not supported");
        require(_preferredCoverage > 0, "Coverage must be positive");
        
        LocationProfile memory locationData = locationProfiles[_location];
        require(_preferredCoverage <= locationData.maxCoverageLimit, "Coverage exceeds location limit");
        
        // Calculate dynamic premium based on risk factors
        uint256 dailyPremium = _calculateDynamicPremium(_location, _preferredCoverage);
        uint256 totalPremium = dailyPremium * _durationDays;
        
        require(msg.value >= totalPremium, "Insufficient premium payment");
        
        // Create new policy
        policyId = nextPolicyId++;
        
        policies[policyId] = InsurancePolicy({
            nomad: msg.sender,
            currentLocation: _location,
            coverageAmount: _preferredCoverage,
            premiumPaid: totalPremium,
            startTimestamp: block.timestamp,
            endTimestamp: block.timestamp + (_durationDays * 1 days),
            locationRiskScore: locationData.riskScore,
            status: PolicyStatus.Active,
            hasActiveClaim: false
        });
        
        nomadPolicies[msg.sender].push(policyId);
        totalInsurancePool += totalPremium;
        totalPoliciesCreated++;
        
        // Refund excess payment
        if (msg.value > totalPremium) {
            payable(msg.sender).transfer(msg.value - totalPremium);
        }
        
        emit PolicyCreated(policyId, msg.sender, _location, _preferredCoverage, totalPremium);
        
        return policyId;
    }
    
    /**
     * @dev Core Function 2: Update location for existing policy with premium adjustment
     * @param _policyId ID of the policy to update
     * @param _newLocation New location of the nomad
     */
    function updateNomadLocation(
        uint256 _policyId,
        string memory _newLocation
    ) external payable validPolicy(_policyId) activePolicyOnly(_policyId) {
        
        require(locationProfiles[_newLocation].isActiveLocation, "New location not supported");
        
        InsurancePolicy storage policy = policies[_policyId];
        string memory oldLocation = policy.currentLocation;
        
        // Calculate remaining policy duration
        uint256 remainingDays = (policy.endTimestamp - block.timestamp) / 1 days;
        require(remainingDays > 0, "Policy expired");
        
        // Calculate premium adjustment for location change
        uint256 oldDailyPremium = _calculateDynamicPremium(oldLocation, policy.coverageAmount);
        uint256 newDailyPremium = _calculateDynamicPremium(_newLocation, policy.coverageAmount);
        
        uint256 premiumAdjustment = 0;
        bool requiresPayment = false;
        
        if (newDailyPremium > oldDailyPremium) {
            premiumAdjustment = (newDailyPremium - oldDailyPremium) * remainingDays;
            requiresPayment = true;
            require(msg.value >= premiumAdjustment, "Insufficient payment for location change");
        }
        
        // Update policy details
        policy.currentLocation = _newLocation;
        policy.locationRiskScore = locationProfiles[_newLocation].riskScore;
        
        if (requiresPayment) {
            policy.premiumPaid += premiumAdjustment;
            totalInsurancePool += premiumAdjustment;
            
            // Refund excess payment
            if (msg.value > premiumAdjustment) {
                payable(msg.sender).transfer(msg.value - premiumAdjustment);
            }
        }
        
        emit LocationUpdated(_policyId, msg.sender, oldLocation, _newLocation, premiumAdjustment);
    }
    
    /**
     * @dev Core Function 3: Submit and process insurance claims
     * @param _policyId Policy ID for the claim
     * @param _claimAmount Amount being claimed
     * @param _description Description of the incident
     * @param _evidenceHash IPFS hash of supporting evidence
     */
    function submitInsuranceClaim(
        uint256 _policyId,
        uint256 _claimAmount,
        string memory _description,
        string memory _evidenceHash
    ) external validPolicy(_policyId) activePolicyOnly(_policyId) returns (uint256 claimId) {
        
        InsurancePolicy storage policy = policies[_policyId];
        require(!policy.hasActiveClaim, "Policy already has an active claim");
        require(_claimAmount > 0 && _claimAmount <= policy.coverageAmount, "Invalid claim amount");
        
        // Check pool has sufficient funds (with reserve)
        uint256 requiredReserve = (totalInsurancePool * POOL_RESERVE_RATIO) / 100;
        require(totalInsurancePool >= _claimAmount + requiredReserve, "Insufficient pool funds");
        
        claimId = nextClaimId++;
        
        claims[claimId] = ClaimRequest({
            claimant: msg.sender,
            policyId: _policyId,
            requestedAmount: _claimAmount,
            claimDescription: _description,
            evidenceHash: _evidenceHash,
            submissionTime: block.timestamp,
            status: ClaimStatus.Pending
        });
        
        policy.hasActiveClaim = true;
        
        // Auto-approve small claims for high-reputation nomads
        if (_shouldAutoApproveClaim(msg.sender, _claimAmount)) {
            _processClaim(claimId, true);
        }
        
        emit ClaimSubmitted(claimId, _policyId, msg.sender, _claimAmount, _description);
        
        return claimId;
    }
    
    /**
     * @dev Calculate dynamic premium based on location risk and coverage
     */
    function _calculateDynamicPremium(
        string memory _location,
        uint256 _coverageAmount
    ) internal view returns (uint256) {
        LocationProfile memory locationData = locationProfiles[_location];
        
        // Base calculation: (base_rate * risk_score * coverage) / normalization_factor
        uint256 premium = (BASE_PREMIUM_RATE * locationData.riskScore * _coverageAmount) / (100 * 1 ether);
        
        // Ensure minimum premium
        return premium < BASE_PREMIUM_RATE ? BASE_PREMIUM_RATE : premium;
    }
    
    /**
     * @dev Process claim approval/rejection
     */
    function _processClaim(uint256 _claimId, bool _approve) internal {
        ClaimRequest storage claim = claims[_claimId];
        InsurancePolicy storage policy = policies[claim.policyId];
        
        if (_approve) {
            claim.status = ClaimStatus.Approved;
            policy.status = PolicyStatus.Claimed;
            
            // Transfer claim amount
            totalInsurancePool -= claim.requestedAmount;
            totalClaimsPaid += claim.requestedAmount;
            payable(claim.claimant).transfer(claim.requestedAmount);
            
            // Update nomad reputation (positive for successful claim)
            nomadReputation[claim.claimant] = _min(nomadReputation[claim.claimant] + 5, 100);
        } else {
            claim.status = ClaimStatus.Rejected;
            policy.hasActiveClaim = false;
        }
        
        emit ClaimProcessed(_claimId, _approve, _approve ? claim.requestedAmount : 0);
    }
    
    /**
     * @dev Check if claim should be auto-approved
     */
    function _shouldAutoApproveClaim(address _nomad, uint256 _amount) internal view returns (bool) {
        return nomadReputation[_nomad] >= 80 && _amount <= 0.1 ether;
    }
    
    /**
     * @dev Initialize location profiles with real-world data
     */
    function _initializeLocationProfiles() internal {
        locationProfiles["Thailand"] = LocationProfile(150, 2 ether, 0.5 ether, true, "Low healthcare costs, moderate safety");
        locationProfiles["Portugal"] = LocationProfile(120, 3 ether, 0.8 ether, true, "EU healthcare, high safety");
        locationProfiles["Mexico"] = LocationProfile(200, 1.5 ether, 0.4 ether, true, "Variable healthcare, safety concerns");
        locationProfiles["Japan"] = LocationProfile(300, 4 ether, 1.2 ether, true, "Expensive healthcare, very safe");
        locationProfiles["Indonesia"] = LocationProfile(180, 2 ether, 0.6 ether, true, "Developing healthcare, moderate risks");
        locationProfiles["Germany"] = LocationProfile(250, 5 ether, 1.5 ether, true, "Excellent healthcare, high costs");
    }
    
    /**
     * @dev Owner function to manually process claims
     */
    function processClaimManually(uint256 _claimId, bool _approve) external onlyOwner {
        require(claims[_claimId].status == ClaimStatus.Pending, "Claim already processed");
        _processClaim(_claimId, _approve);
    }
    
    /**
     * @dev Allow community contributions to insurance pool
     */
    function contributeToInsurancePool() external payable {
        require(msg.value > 0, "Must contribute positive amount");
        totalInsurancePool += msg.value;
        emit PoolContribution(msg.sender, msg.value);
    }
    
    /**
     * @dev Get nomad's policy history
     */
    function getNomadPolicies(address _nomad) external view returns (uint256[] memory) {
        return nomadPolicies[_nomad];
    }
    
    /**
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 poolBalance,
        uint256 totalPolicies,
        uint256 totalClaims,
        uint256 poolUtilization
    ) {
        poolUtilization = totalInsurancePool > 0 ? (totalClaimsPaid * 100) / totalInsurancePool : 0;
        return (totalInsurancePool, totalPoliciesCreated, totalClaimsPaid, poolUtilization);
    }
    
    /**
     * @dev Utility function for minimum calculation
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /**
     * @dev Emergency withdrawal (owner only)
     */
    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance, "Insufficient contract balance");
        payable(owner).transfer(_amount);
    }
}
